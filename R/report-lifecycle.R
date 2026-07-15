report_plan_value <- function(plan, key, default) {
  if (is.null(plan) || !inherits(plan, "dcc_plan") || !nrow(plan$outputs)) {
    return(default)
  }
  index <- match(key, as.character(plan$outputs$key))
  if (is.na(index)) default else as.character(plan$outputs$value[index])
}

report_plan_logical <- function(plan, key, default = TRUE) {
  value <- report_plan_value(plan, key, as.character(default))
  identical(toupper(as.character(value)), "TRUE")
}

report_run_options <- function(plan) {
  statistical <- if (!is.null(plan) &&
                     "include_statistical_report" %in% plan$outputs$key) {
    report_plan_logical(plan, "include_statistical_report", TRUE)
  } else {
    report_plan_logical(plan, "include_audit_report", TRUE)
  }
  list(
    language = report_plan_value(
      plan, "report_language", plan$project$language %||% "zh-CN"
    ),
    staff = report_plan_logical(plan, "include_staff_report", TRUE),
    statistical = statistical,
    machine = report_plan_logical(plan, "include_machine_report", TRUE),
    statistical_table_format = tolower(report_plan_value(
      plan, "statistical_table_format", "parquet"
    )),
    include_examples = report_plan_logical(
      plan, "include_sensitive_examples", FALSE
    )
  )
}

new_report_state <- function(selected) {
  list(
    status = if (selected) "pending" else "skipped",
    required = isTRUE(selected),
    files = character(),
    error = NULL
  )
}

render_audience_reports <- function(result, config, id_var, core_files,
                                    staging, mode, run_id, plan) {
  options <- report_run_options(plan)
  selected <- c(
    staff = options$staff,
    statistical = options$statistical,
    machine = options$machine
  )
  reports <- lapply(selected, new_report_state)
  base_status <- if (mode == "preview") "preview" else "success"
  context <- new_dcc_run(mode, config, id_var, core_files, result, run_id)
  context$run_dir <- staging
  context$status <- base_status
  context$plan <- plan
  model <- dcc_report_model(result, context)
  renderers <- list(
    staff = function(path) dcc_report_staff(
      model, path, language = options$language,
      include_examples = options$include_examples
    ),
    statistical = function(path) dcc_report_statistical(
      model, path, table_format = options$statistical_table_format
    ),
    machine = function(path) dcc_report_machine(model, path)
  )
  written <- character()
  for (audience in names(selected)[selected]) {
    reports[[audience]]$status <- "writing"
    value <- tryCatch(
      renderers[[audience]](file.path(staging, audience)),
      error = function(e) e
    )
    if (inherits(value, "error")) {
      reports[[audience]]$status <- "failed"
      reports[[audience]]$error <- conditionMessage(value)
    } else {
      reports[[audience]]$status <- "success"
      reports[[audience]]$files <- machine_relative_paths(value, staging)
      written <- c(written, value)
    }
  }
  status <- if (any(vapply(reports, function(x) x$status == "failed",
                           logical(1)))) {
    "partial_failure"
  } else {
    base_status
  }
  model$run$status <- status
  list(status = status, reports = reports, files = written, model = model)
}

build_run_manifest <- function(lifecycle, mode, run_id, files, staging) {
  model <- lifecycle$model
  list(
    contract_version = "1.0",
    run_id = run_id,
    status = lifecycle$status,
    mode = mode,
    reports = lifecycle$reports,
    counts = model$summaries[c(
      "input_rows", "output_rows", "findings_total", "changes_total",
      "excluded_total", "handled_total", "unhandled_total"
    )],
    hashes = model$hashes,
    core_artifacts = machine_relative_paths(files, staging)
  )
}

write_run_manifest <- function(manifest, path) {
  report_write_json(manifest, path)
  invisible(path)
}
