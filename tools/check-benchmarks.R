#!/usr/bin/env Rscript

benchmark_required_stages <- function() {
  c(
    "import", "canonicalization", "validation", "detection", "preview",
    "execution", "report_model", "staff", "statistical", "machine"
  )
}

benchmark_failure <- function(code, stage = NA_character_, detail = "") {
  data.frame(
    code = as.character(code), stage = as.character(stage),
    detail = as.character(detail), stringsAsFactors = FALSE
  )
}

compare_benchmarks <- function(current, baseline, regression_limit = 0.20,
                               execution_budget = 45, minimum_runs = 3L) {
  failures <- list()
  add_failure <- function(code, stage = NA_character_, detail = "") {
    failures[[length(failures) + 1L]] <<-
      benchmark_failure(code, stage, detail)
  }
  required_current <- c(
    "platform_class", "run", "stage", "seconds", "peak_memory_bytes",
    "correctness"
  )
  required_baseline <- c(
    "platform_class", "stage", "median_seconds", "peak_memory_bytes"
  )
  absent_current <- setdiff(required_current, names(current))
  absent_baseline <- setdiff(required_baseline, names(baseline))
  if (length(absent_current) || length(absent_baseline)) {
    add_failure(
      "BENCHMARK_CONTRACT_INVALID", detail = paste(
        c(
          if (length(absent_current)) paste0("current:", paste(absent_current, collapse = ",")),
          if (length(absent_baseline)) paste0("baseline:", paste(absent_baseline, collapse = ","))
        ),
        collapse = "; "
      )
    )
    return(list(
      ok = FALSE, comparison = data.frame(),
      failures = do.call(rbind, failures)
    ))
  }

  current_platform <- unique(as.character(current$platform_class))
  baseline_platform <- unique(as.character(baseline$platform_class))
  if (length(current_platform) != 1L || length(baseline_platform) != 1L ||
      !identical(current_platform, baseline_platform)) {
    add_failure(
      "BENCHMARK_PLATFORM_MISMATCH",
      detail = paste("current", paste(current_platform, collapse = ","),
                     "baseline", paste(baseline_platform, collapse = ","))
    )
  }

  required <- benchmark_required_stages()
  missing_current <- setdiff(required, unique(as.character(current$stage)))
  missing_baseline <- setdiff(required, unique(as.character(baseline$stage)))
  for (stage in unique(c(missing_current, missing_baseline))) {
    add_failure("BENCHMARK_STAGE_MISSING", stage)
  }
  common <- intersect(required, intersect(current$stage, baseline$stage))
  summaries <- lapply(common, function(stage) {
    values <- current[current$stage == stage, , drop = FALSE]
    run_count <- length(unique(values$run))
    if (run_count < minimum_runs) {
      add_failure(
        "BENCHMARK_RUNS_INSUFFICIENT", stage,
        paste(run_count, "runs; require", minimum_runs)
      )
    }
    if (any(!as.logical(values$correctness)) || anyNA(values$correctness)) {
      add_failure("BENCHMARK_CORRECTNESS_FAILED", stage)
    }
    reference <- baseline[baseline$stage == stage, , drop = FALSE]
    current_seconds <- stats::median(as.numeric(values$seconds), na.rm = TRUE)
    current_memory <- stats::median(
      as.numeric(values$peak_memory_bytes), na.rm = TRUE
    )
    baseline_seconds <- as.numeric(reference$median_seconds[1L])
    baseline_memory <- as.numeric(reference$peak_memory_bytes[1L])
    relative <- current_seconds / baseline_seconds - 1
    relative_memory <- current_memory / baseline_memory - 1
    if (!is.finite(relative) || relative > regression_limit) {
      add_failure(
        "BENCHMARK_REGRESSION", stage,
        sprintf("time change %.1f%% exceeds %.1f%%", 100 * relative,
                100 * regression_limit)
      )
    }
    if (!is.finite(relative_memory) || relative_memory > regression_limit) {
      add_failure(
        "BENCHMARK_MEMORY_REGRESSION", stage,
        sprintf("memory change %.1f%% exceeds %.1f%%", 100 * relative_memory,
                100 * regression_limit)
      )
    }
    if (identical(stage, "execution") &&
        (!is.finite(current_seconds) || current_seconds > execution_budget)) {
      add_failure(
        "BENCHMARK_EXECUTION_BUDGET", stage,
        sprintf("median %.3fs exceeds %.3fs", current_seconds,
                execution_budget)
      )
    }
    data.frame(
      stage = stage, median_seconds = current_seconds,
      baseline_seconds = baseline_seconds, relative_change = relative,
      peak_memory_bytes = current_memory,
      baseline_peak_memory_bytes = baseline_memory,
      relative_memory_change = relative_memory,
      stringsAsFactors = FALSE
    )
  })
  comparison <- if (length(summaries)) do.call(rbind, summaries) else
    data.frame()
  failure_table <- if (length(failures)) do.call(rbind, failures) else
    data.frame(code = character(), stage = character(), detail = character(),
               stringsAsFactors = FALSE)
  list(ok = nrow(failure_table) == 0L, comparison = comparison,
       failures = failure_table)
}

benchmark_argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  current_path <- benchmark_argument(
    args, "current", "artifacts/benchmark-current.json"
  )
  baseline_path <- benchmark_argument(
    args, "baseline", "benchmarks/baseline.json"
  )
  if (!file.exists(current_path)) {
    stop("Current benchmark evidence does not exist: ", current_path)
  }
  if (!file.exists(baseline_path)) {
    stop("Accepted benchmark baseline does not exist: ", baseline_path)
  }
  current <- jsonlite::read_json(current_path, simplifyVector = TRUE)
  baseline <- jsonlite::read_json(baseline_path, simplifyVector = TRUE)
  if (!isTRUE(baseline$accepted)) {
    cat("BENCHMARK: BLOCKED (baseline is not accepted)\n")
    quit(status = 1L)
  }
  result <- compare_benchmarks(current$records, baseline$stages)
  if (nrow(result$comparison)) print(result$comparison, row.names = FALSE)
  if (!result$ok) {
    print(result$failures, row.names = FALSE)
    cat("BENCHMARK: FAIL\n")
    quit(status = 1L)
  }
  cat("BENCHMARK: PASS\n")
}

if (sys.nframe() == 0L) main()
