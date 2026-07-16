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

argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

write_evidence <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    value, path, auto_unbox = TRUE, dataframe = "rows", na = "null",
    null = "null", pretty = TRUE, digits = NA
  )
  normalizePath(path, mustWork = TRUE)
}

load_dcc <- function(root) {
  if (!requireNamespace("DCC", quietly = TRUE)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("Install DCC first, or install pkgload to run from source.")
    }
    pkgload::load_all(root, quiet = TRUE)
  }
  if (!"package:DCC" %in% search()) {
    suppressPackageStartupMessages(library("DCC", character.only = TRUE))
  }
}

run_staff <- function(root, output_dir, mode) {
  if (!identical(mode, "synthetic")) {
    stop("Staff acceptance supports --mode=synthetic only.")
  }
  scenarios <- yaml::read_yaml(
    file.path(root, "tests", "acceptance", "staff", "scenarios.yml")
  )
  required <- c(
    "completion_rate", "preview_execution_distinction_rate", "median_sus",
    "maximum_minutes", "maximum_code_edits", "maximum_raw_overwrites"
  )
  if (!isTRUE(scenarios$human_evidence_required) ||
      length(setdiff(required, names(scenarios$thresholds))) ||
      length(scenarios$scenarios) < 7L) {
    stop("Staff acceptance scenario contract is invalid.")
  }
  template <- file.path(
    root, "tests", "acceptance", "staff", "facilitator-template.xlsx"
  )
  if (!file.exists(template)) stop("Facilitator workbook is missing.")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  workbook <- file.path(output_dir, "staff-facilitator.xlsx")
  if (!file.copy(template, workbook, overwrite = TRUE)) {
    stop("Could not copy facilitator workbook.")
  }
  evidence <- list(
    contract_version = "1.0", audience = "staff", mode = mode,
    status = "facilitator_required", human_evidence = FALSE,
    scenario_contract_valid = TRUE,
    facilitator_workbook = normalizePath(workbook, mustWork = TRUE),
    participant_records = 0L,
    message = paste(
      "Automated preparation is not human usability evidence;",
      "signed participant sessions are required."
    )
  )
  path <- write_evidence(evidence, file.path(output_dir, "staff-evidence.json"))
  cat("STAFF ACCEPTANCE: FACILITATOR REQUIRED\n", path, "\n")
  invisible(evidence)
}

new_spec <- function(path, format, columns) {
  DCC:::new_import_spec(
    path, format, options = if (format == "csv") list(encoding = "UTF-8") else list(),
    columns = columns,
    missing = data.frame(
      variable = character(), source_value = character(), state = character(),
      stringsAsFactors = FALSE
    )
  )
}

statistician_fixture <- function() {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S001,90", "S002,150", "S003,70"), csv)
  columns <- data.frame(
    source_name = c("sid", "score"), name = c("sid", "score"),
    type = c("character", "double"), role = c("id", "score"),
    stringsAsFactors = FALSE
  )
  rules_path <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:", "  - id: R001", "    type: range",
    "    variable: score", "    min: 0", "    max: 100",
    "    severity: fail"
  ), rules_path)
  list(
    csv = csv, spec = new_spec(csv, "csv", columns),
    rules = dcc_rules(rules_path), rules_path = rules_path
  )
}

run_statistician <- function(root, output_dir, mode) {
  if (!identical(mode, "synthetic")) {
    stop("Statistician acceptance supports --mode=synthetic only.")
  }
  load_dcc(root)
  scenarios <- yaml::read_yaml(file.path(
    root, "tests", "acceptance", "statistician", "scenarios.yml"
  ))
  fixture <- statistician_fixture()
  on.exit(unlink(c(fixture$csv, fixture$rules_path)), add = TRUE)
  imported <- dcc_import(fixture$csv, fixture$spec)
  findings <- dcc_detect(imported, fixture$rules, id_var = "sid")
  preview <- dcc_execute(imported, findings, actions = list(), id_var = "sid")
  applied <- dcc_execute(
    imported, findings, actions = list(R001 = "set_na"), id_var = "sid"
  )
  checks <- list()
  add_check <- function(id, value, detail = "") {
    checks[[length(checks) + 1L]] <<- data.frame(
      id = id, passed = isTRUE(value), detail = detail,
      stringsAsFactors = FALSE
    )
  }
  add_check(
    "programmatic-import",
    inherits(imported, "dcc_data") && identical(imported$data$sid, c("S001", "S002", "S003")) &&
      is.double(imported$data$score)
  )

  sav <- tempfile(fileext = ".sav")
  on.exit(unlink(sav), add = TRUE)
  labelled <- data.frame(
    sid = c("S001", "S002"),
    q1 = haven::labelled_spss(
      c(1, 9), labels = c(Yes = 1, Missing = 9), na_values = 9,
      label = "Question 1"
    )
  )
  haven::write_sav(labelled, sav)
  labelled_spec <- new_spec(sav, "spss", data.frame(
    source_name = c("sid", "q1"), name = c("sid", "q1"),
    type = c("character", "integer"), role = c("id", "item"),
    stringsAsFactors = FALSE
  ))
  labelled_data <- dcc_import(sav, labelled_spec)
  add_check(
    "labelled-missing",
    identical(dcc_dictionary(labelled_data)$label[2L], "Question 1") &&
      "declared_missing_code" %in% dcc_missing_states(labelled_data)$state
  )
  add_check(
    "custom-rules",
    nrow(findings) == 1L && identical(as.character(findings$check_id), "R001")
  )
  add_check(
    "preview-apply",
    nrow(dcc_audit_log(preview)) == 0L && nrow(dcc_audit_log(applied)) == 1L &&
      is.na(dcc_cleaned(applied)$data$score[2L])
  )
  repeated <- dcc_detect(imported, fixture$rules, id_var = "sid")
  add_check(
    "reproducibility",
    identical(findings$finding_id, repeated$finding_id)
  )
  report_dir <- tempfile("dcc-stat-acceptance-")
  on.exit(unlink(report_dir, recursive = TRUE), add = TRUE)
  files <- dcc_report_statistical(
    dcc_report_model(applied), report_dir, table_format = "csv"
  )
  manifest <- jsonlite::read_json(
    file.path(report_dir, "artifact-manifest.json"), simplifyVector = TRUE
  )
  add_check(
    "full-table-export",
    all(file.exists(files)) && nrow(manifest$artifacts) == length(files) - 1L
  )
  provenance <- dcc_provenance(dcc_cleaned(applied))
  add_check(
    "provenance",
    all(c("import", "execute") %in% provenance$stage) &&
      nzchar(imported$meta$file_hash)
  )
  legacy <- dcc_read(fixture$csv)
  legacy_findings <- dcc_detect(legacy, fixture$rules, id_var = "sid")
  legacy_result <- dcc_execute(
    legacy, legacy_findings, actions = list(R001 = "set_na"), id_var = "sid"
  )
  add_check(
    "legacy-migration",
    inherits(legacy_result, "dcc_result") && nrow(dcc_audit_log(legacy_result)) == 1L,
    "Legacy calls work; strict plans remain recommended for new workflows."
  )
  results <- do.call(rbind, checks)
  expected_ids <- vapply(scenarios$scenarios, `[[`, character(1), "id")
  if (!setequal(results$id, expected_ids)) stop("Statistician scenario IDs diverged.")
  evidence <- list(
    contract_version = "1.0", audience = "statistician", mode = mode,
    status = if (all(results$passed)) "pass" else "fail",
    correctness = results,
    caveats = c(
      "DCC does not select inferential models or estimate sampling uncertainty.",
      "Format capability levels and sensitive-data policy remain part of interpretation.",
      "Legacy calls are supported, but strict plans are recommended for new projects."
    )
  )
  path <- write_evidence(
    evidence, file.path(output_dir, "statistician-evidence.json")
  )
  if (!all(results$passed)) {
    print(results[!results$passed, ], row.names = FALSE)
    cat("STATISTICIAN ACCEPTANCE: FAIL\n")
    quit(status = 1L)
  }
  cat("STATISTICIAN ACCEPTANCE: PASS\n", path, "\n")
  invisible(evidence)
}

run_agent <- function(root, output_dir, mode) {
  if (!identical(mode, "contract")) {
    stop("Agent acceptance supports --mode=contract only.")
  }
  suite <- jsonlite::read_json(
    file.path(root, "tests", "acceptance", "agent", "tasks.json"),
    simplifyVector = FALSE
  )
  schema <- jsonlite::read_json(
    file.path(root, "inst", "schemas", "agent-task-result.schema.json"),
    simplifyVector = FALSE
  )
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\(([^)]+)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  ids <- vapply(suite$tasks, `[[`, character(1), "id")
  allowed <- unique(unlist(lapply(suite$tasks, `[[`, "allowed_public_calls")))
  gated <- vapply(suite$tasks, function(task) {
    !isTRUE(task$permits_execution) ||
      (isTRUE(task$requires_validation) && isTRUE(task$requires_preview))
  }, logical(1))
  valid <- identical(suite$contract_version, "1.0") &&
    length(suite$tasks) >= 20L && !anyDuplicated(ids) &&
    !length(setdiff(allowed, exports)) && all(gated) &&
    identical(schema$additionalProperties, FALSE) &&
    length(schema$required) == 10L
  evidence <- list(
    contract_version = "1.0", audience = "agent", mode = mode,
    status = if (valid) "contract_pass" else "fail",
    task_count = length(suite$tasks), success_threshold = suite$thresholds$success_rate,
    maximum_attempts = suite$thresholds$maximum_attempts,
    execution_tasks_gated = all(gated), unknown_public_calls = setdiff(allowed, exports),
    task_results_present = FALSE,
    message = "Contract validation is not an AI-agent execution score."
  )
  path <- write_evidence(evidence, file.path(output_dir, "agent-contract.json"))
  if (!valid) {
    cat("AGENT CONTRACT: FAIL\n")
    quit(status = 1L)
  }
  cat("AGENT CONTRACT: PASS (execution evidence still required)\n", path, "\n")
  invisible(evidence)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  audience <- argument(args, "audience")
  mode <- argument(args, "mode")
  if (is.null(audience) || !audience %in% c("staff", "statistician", "agent")) {
    stop("--audience must be staff, statistician, or agent.")
  }
  if (is.null(mode)) stop("--mode is required.")
  root <- find_project_root()
  output <- argument(
    args, "output", file.path(root, "artifacts", "acceptance", audience)
  )
  switch(
    audience,
    staff = run_staff(root, output, mode),
    statistician = run_statistician(root, output, mode),
    agent = run_agent(root, output, mode)
  )
}

if (sys.nframe() == 0L) main()
