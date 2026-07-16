#!/usr/bin/env Rscript

find_project_root <- function(path = getwd()) {
  path <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate DCC project root.")
    path <- parent
  }
}

project_root <- find_project_root()
if (!requireNamespace("DCC", quietly = TRUE)) {
  if (!requireNamespace("pkgload", quietly = TRUE)) {
    stop("Install DCC first, or install pkgload to benchmark from source.")
  }
  pkgload::load_all(project_root, quiet = TRUE)
}
if (!"package:DCC" %in% search()) {
  suppressPackageStartupMessages(library("DCC", character.only = TRUE))
}
suppressPackageStartupMessages(library(data.table))

argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

platform_class <- function() {
  r_minor <- paste(R.version$major, strsplit(R.version$minor, "\\.")[[1L]][1L],
                   sep = ".")
  paste(Sys.info()[["sysname"]], R.version$arch, paste0("R", r_minor), sep = "-")
}

cpu_class <- function() {
  runner <- Sys.getenv("RUNNER_ARCH", "")
  if (nzchar(runner)) return(paste("GitHub", runner))
  paste(Sys.info()[["machine"]], Sys.info()[["release"]])
}

package_versions <- function() {
  fields <- read.dcf(file.path(project_root, "DESCRIPTION"),
                     fields = c("Imports", "Suggests"))[1L, ]
  packages <- unique(trimws(unlist(strsplit(paste(fields, collapse = ","), ","))))
  packages <- sub("\\s*\\(.*$", "", packages)
  packages <- packages[nzchar(packages)]
  versions <- vapply(packages, function(package) {
    if (requireNamespace(package, quietly = TRUE)) {
      as.character(utils::packageVersion(package))
    } else {
      NA_character_
    }
  }, character(1))
  as.list(versions)
}

heap_peak_bytes <- function(gc_result) {
  as.numeric(gc_result["Ncells", "max used"]) * 56 +
    as.numeric(gc_result["Vcells", "max used"]) * 8
}

measure_stage <- function(stage, run, expression, correctness,
                          context) {
  invisible(gc(reset = TRUE))
  started <- proc.time()[["elapsed"]]
  value <- force(expression)
  elapsed <- proc.time()[["elapsed"]] - started
  memory <- heap_peak_bytes(gc())
  correct <- isTRUE(correctness(value))
  record <- data.frame(
    platform_class = context$platform_class,
    cpu_class = context$cpu_class,
    r_version = R.version.string,
    dcc_version = as.character(utils::packageVersion("DCC")),
    run = as.integer(run), stage = stage,
    rows = context$rows, columns = context$columns,
    findings = context$findings, actions = context$actions,
    seconds = as.numeric(elapsed), peak_memory_bytes = memory,
    input_bytes = context$input_bytes, correctness = correct,
    stringsAsFactors = FALSE
  )
  if (!correct) stop("Correctness assertion failed for benchmark stage: ", stage)
  list(value = value, record = record)
}

generate_data <- function(n) {
  set.seed(42)
  data <- data.table(
    sid = sprintf("S%08d", seq_len(n)),
    grp = sample(c("A", "B", "C"), n, replace = TRUE),
    time_total = pmax(10, stats::rnorm(n, 600, 120)),
    trap1 = sample(c(3, 3, 3, 3, 1), n, replace = TRUE),
    score = round(pmin(100, pmax(0, stats::rnorm(n, 70, 12))), 1)
  )
  for (name in paste0("q", seq_len(20L))) {
    data.table::set(
      data, j = name,
      value = sample(c(1:5, NA_integer_), n, replace = TRUE,
                     prob = c(rep(0.19, 5), 0.05))
    )
  }
  bad <- seq.int(1L, n, by = 100L)
  data.table::set(data, i = bad, j = "score", value = 150)
  data
}

import_spec <- function(path, data) {
  types <- vapply(data, function(column) {
    if (is.integer(column)) "integer"
    else if (is.numeric(column)) "double"
    else "character"
  }, character(1))
  columns <- data.frame(
    source_name = names(data), name = names(data), type = types,
    role = ifelse(names(data) == "sid", "id", "other"),
    stringsAsFactors = FALSE
  )
  DCC:::new_import_spec(
    path, "csv", options = list(encoding = "UTF-8"),
    columns = columns,
    missing = data.frame(
      variable = character(), source_value = character(),
      state = character(), stringsAsFactors = FALSE
    )
  )
}

benchmark_rules <- function() {
  path <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    min: 0",
    "    max: 100",
    "    severity: fail"
  ), path)
  on.exit(unlink(path), add = TRUE)
  dcc_rules(path)
}

run_once <- function(run, csv, source_data, spec, rules, context) {
  records <- list()
  capture <- function(result) {
    records[[length(records) + 1L]] <<- result$record
    result$value
  }

  adapter <- DCC:::dcc_get_adapter("csv")
  raw <- capture(measure_stage(
    "import", run,
    adapter$reader(csv, list(encoding = "UTF-8")),
    function(value) is.list(value) && nrow(value$data) == context$rows,
    context
  ))
  canonical <- capture(measure_stage(
    "canonicalization", run,
    DCC:::canonicalize_import(raw$data, raw$metadata, spec),
    function(value) inherits(value, "dcc_data") &&
      nrow(value$data) == context$rows && ncol(value$data) == context$columns,
    context
  ))
  validation <- capture(measure_stage(
    "validation", run,
    dcc_validate_data(canonical, rules, id_var = "sid"),
    function(value) inherits(value, "dcc_validation") &&
      nrow(dcc_validation_errors(value)) == 0L,
    context
  ))
  findings <- capture(measure_stage(
    "detection", run,
    dcc_detect(canonical, rules, id_var = "sid"),
    function(value) nrow(value) == length(seq.int(1L, context$rows, by = 100L)),
    context
  ))
  context$findings <- nrow(findings)
  context$actions <- nrow(findings)
  preview <- capture(measure_stage(
    "preview", run,
    dcc_execute(canonical, findings, actions = list(), id_var = "sid"),
    function(value) nrow(dcc_audit_log(value)) == 0L &&
      identical(dcc_cleaned(value)$data$score, canonical$data$score),
    context
  ))
  result <- capture(measure_stage(
    "execution", run,
    dcc_execute(
      canonical, findings, actions = list(R001 = "set_na"), id_var = "sid"
    ),
    function(value) nrow(dcc_audit_log(value)) == nrow(findings) &&
      sum(is.na(dcc_cleaned(value)$data$score)) == nrow(findings),
    context
  ))
  model <- capture(measure_stage(
    "report_model", run,
    dcc_report_model(result),
    function(value) inherits(value, "dcc_report_model") &&
      nrow(dcc_validation_errors(dcc_validate_report_model(value))) == 0L,
    context
  ))
  staff_dir <- tempfile("dcc-bench-staff-")
  staff <- capture(measure_stage(
    "staff", run,
    dcc_report_staff(model, staff_dir),
    function(value) length(value) == 3L && all(file.exists(value)),
    context
  ))
  statistical_dir <- tempfile("dcc-bench-statistical-")
  statistical <- capture(measure_stage(
    "statistical", run,
    dcc_report_statistical(model, statistical_dir, table_format = "csv"),
    function(value) length(value) >= 4L && all(file.exists(value)),
    context
  ))
  machine_dir <- tempfile("dcc-bench-machine-")
  machine <- capture(measure_stage(
    "machine", run,
    dcc_report_machine(model, machine_dir),
    function(value) all(file.exists(value)),
    context
  ))
  unlink(c(staff_dir, statistical_dir, machine_dir), recursive = TRUE)
  table <- do.call(rbind, records)
  table$findings <- nrow(findings)
  table$actions <- nrow(findings)
  table
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  rows <- as.integer(argument(
    args, "rows", Sys.getenv("DCC_BENCH_ROWS", "1000000")
  ))
  runs <- as.integer(argument(args, "runs", "3"))
  output <- argument(
    args, "output", Sys.getenv("DCC_BENCH_OUT", "artifacts/benchmark-current.json")
  )
  if (length(rows) != 1L || is.na(rows) || rows < 1L) stop("--rows must be positive.")
  if (length(runs) != 1L || is.na(runs) || runs < 3L) stop("--runs must be at least 3.")

  source_data <- generate_data(rows)
  csv <- tempfile(fileext = ".csv")
  data.table::fwrite(source_data, csv)
  on.exit(unlink(csv), add = TRUE)
  spec <- import_spec(csv, source_data)
  rules <- benchmark_rules()
  context <- list(
    platform_class = platform_class(), cpu_class = cpu_class(),
    rows = rows, columns = ncol(source_data), findings = NA_integer_,
    actions = NA_integer_, input_bytes = as.numeric(file.size(csv))
  )
  records <- do.call(rbind, lapply(seq_len(runs), function(run) {
    message(sprintf("benchmark run %d/%d (%s rows)", run, runs,
                    format(rows, big.mark = ",", scientific = FALSE)))
    run_once(run, csv, source_data, spec, rules, context)
  }))
  stages <- split(records, records$stage)
  summary <- do.call(rbind, lapply(stages, function(stage) {
    data.frame(
      platform_class = stage$platform_class[1L],
      cpu_class = stage$cpu_class[1L], stage = stage$stage[1L],
      median_seconds = stats::median(stage$seconds),
      peak_memory_bytes = stats::median(stage$peak_memory_bytes),
      stringsAsFactors = FALSE
    )
  }))
  summary <- summary[match(
    c("import", "canonicalization", "validation", "detection", "preview",
      "execution", "report_model", "staff", "statistical", "machine"),
    summary$stage
  ), , drop = FALSE]
  evidence <- list(
    contract_version = "1.1", generated_at = format(
      Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    platform_class = context$platform_class, cpu_class = context$cpu_class,
    rows = rows, columns = context$columns, runs = runs,
    package_versions = package_versions(), records = records, summary = summary
  )
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    evidence, output, auto_unbox = TRUE, dataframe = "rows", na = "null",
    null = "null", pretty = TRUE, digits = NA
  )
  print(summary, row.names = FALSE)
  cat("BENCHMARK CAPTURE: PASS\n")
  cat(normalizePath(output, mustWork = TRUE), "\n")
}

main()
