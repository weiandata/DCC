# DCC performance benchmark (design section 8).
#
# Generates synthetic assessment data, runs the read -> detect ->
# execute pipeline, prints machine-readable timings, and exits non-zero
# when a stage breaches its per-scale threshold (CI regression gate).
#
# Usage:
#   Rscript benchmarks/benchmark.R            # 1e4 and 1e6 rows
#   DCC_BENCH_ROWS="10000,1000000,10000000" Rscript benchmarks/benchmark.R
#
# Thresholds are deliberately generous: they catch order-of-magnitude
# regressions, not machine noise.

suppressPackageStartupMessages({
  library(DCC)
  library(data.table)
})

rows_env <- Sys.getenv("DCC_BENCH_ROWS", "10000,1000000")
scales <- as.numeric(strsplit(rows_env, ",")[[1]])

# seconds allowed per stage, scaled per million rows (minimum 5s)
budget <- function(n, per_million) max(5, per_million * n / 1e6)
budgets <- list(read = 30, detect = 60, execute = 60)

gen_data <- function(n) {
  set.seed(42)
  dt <- data.table(
    sid = sprintf("S%08d", seq_len(n)),
    grp = sample(c("A", "B", "C"), n, replace = TRUE),
    time_total = pmax(10, stats::rnorm(n, 600, 120)),
    trap1 = sample(c(3, 3, 3, 3, 1), n, replace = TRUE),
    score = pmin(100, pmax(0, stats::rnorm(n, 70, 12)))
  )
  for (j in paste0("q", 1:20)) {
    v <- sample(c(1:5, NA), n, replace = TRUE,
                prob = c(rep(0.19, 5), 0.05))
    data.table::set(dt, j = j, value = v)
  }
  # inject violations (~1%)
  bad <- sample(n, max(1, n %/% 100))
  data.table::set(dt, i = bad, j = "score",
                  value = stats::runif(length(bad), 101, 200))
  dt
}

rules_yaml <- '
checks:
  - id: R001
    type: range
    variable: score
    min: 0
    max: 100
    severity: fail
  - id: D001
    type: straightlining
    items: [q1, q2, q3, q4, q5, q6, q7, q8, q9, q10,
            q11, q12, q13, q14, q15, q16, q17, q18, q19, q20]
    max_run: 15
  - id: D002
    type: missing_items
    items: [q1, q2, q3, q4, q5, q6, q7, q8, q9, q10,
            q11, q12, q13, q14, q15, q16, q17, q18, q19, q20]
    max_prop: 0.5
  - id: D003
    type: trap_items
    traps:
      trap1: 3
'

results <- list()
failed <- FALSE

for (n in scales) {
  message(sprintf("== scale: %g rows ==", n))
  dt <- gen_data(n)
  csv <- tempfile(fileext = ".csv")
  fwrite(dt, csv)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(rules_yaml, rules_file)
  rules <- dcc_rules(rules_file)

  t_read <- system.time(x <- dcc_read(csv))[["elapsed"]]
  t_detect <- system.time(
    f <- dcc_detect(x, rules, id_var = "sid")
  )[["elapsed"]]
  t_execute <- system.time(
    # Only declare actions for checks that fire on this synthetic data:
    # unused action IDs are rejected (dcc_execute validates the plan), and
    # the clean random items trigger neither straightlining nor >50%
    # missingness. R001 (~1% out-of-range) and Q_TRAP_ITEMS (~20% failed
    # trap) supply the execute-stage change volume the benchmark times.
    res <- dcc_execute(x, f,
                       actions = list(R001 = "set_na",
                                      Q_TRAP_ITEMS = "flag"),
                       id_var = "sid")
  )[["elapsed"]]

  for (stage in names(budgets)) {
    t <- switch(stage, read = t_read, detect = t_detect,
                execute = t_execute)
    lim <- budget(n, budgets[[stage]])
    ok <- t <= lim
    if (!ok) failed <- TRUE
    results[[length(results) + 1L]] <- data.table(
      rows = n, stage = stage, seconds = round(t, 2),
      limit = round(lim, 2), ok = ok,
      findings = nrow(f), changes = nrow(dcc_audit_log(res))
    )
  }

  # Larger-than-memory backends (design section 8). Every benchmark
  # check (range, straightlining, missing_items, trap_items) is
  # chunk-safe, so the streaming paths reuse the same rule set. These
  # stages are informational -- they exercise the streaming backends at
  # scale without a hard budget, since backend speed depends heavily on
  # the host I/O layer.
  t_csv_chunk <- system.time(
    fc <- dcc_detect_chunked(csv, rules, id_var = "sid",
                             backend = "csv", encoding = "UTF-8")
  )[["elapsed"]]
  results[[length(results) + 1L]] <- data.table(
    rows = n, stage = "chunked_csv", seconds = round(t_csv_chunk, 2),
    limit = NA_real_, ok = TRUE,
    findings = nrow(fc), changes = NA_integer_
  )
  if (requireNamespace("arrow", quietly = TRUE)) {
    pq <- tempfile(fileext = ".parquet")
    arrow::write_parquet(dt, pq)
    t_arrow_chunk <- system.time(
      fa <- dcc_detect_chunked(pq, rules, id_var = "sid")
    )[["elapsed"]]
    results[[length(results) + 1L]] <- data.table(
      rows = n, stage = "chunked_arrow",
      seconds = round(t_arrow_chunk, 2),
      limit = NA_real_, ok = TRUE,
      findings = nrow(fa), changes = NA_integer_
    )
    unlink(pq)
  }
  unlink(c(csv, rules_file))
}

out <- rbindlist(results)
message("\n== DCC benchmark results ==")
print(out)
csv_out <- Sys.getenv("DCC_BENCH_OUT", "")
if (nzchar(csv_out)) {
  fwrite(out, csv_out)
}
if (failed) {
  message("BENCHMARK REGRESSION: at least one stage over budget")
  quit(status = 1)
}
message("all stages within budget")
