#' Build the normalized report model
#'
#' Creates the single, versioned source of truth used by DCC's staff,
#' statistical, and machine report renderers. The constructor copies values
#' from the cleaning result and optional run object; renderers must not
#' recompute cleaning statistics from the original result.
#'
#' @param result A `dcc_result` returned by [dcc_execute()].
#' @param run Optional `dcc_run` that owns `result` and supplies run, plan, and
#'   output metadata.
#' @return A `dcc_report_model` list with contract version `1.0`.
#' @export
dcc_report_model <- function(result, run = NULL) {
  if (!inherits(result, "dcc_result")) {
    dcc_abort("`result` must be a dcc_result from dcc_execute().",
              class = "dcc_type_error")
  }
  if (!is.null(run) && !inherits(run, "dcc_run")) {
    dcc_abort("`run` must be a dcc_run or NULL.", class = "dcc_type_error")
  }
  if (!is.null(run) && !identical(run$result, result)) {
    dcc_abort("`run$result` must be the supplied `result`.",
              class = "dcc_report_model_error")
  }

  findings <- report_copy_table(result$findings)
  findings$count <- rep.int(1L, nrow(findings))
  dispositions <- report_copy_table(result$dispositions)
  changes <- report_copy_table(result$audit)
  reconciliation <- report_copy_table(dcc_reconcile(result))
  exclusions <- changes[changes$action == "exclude", , drop = FALSE]
  rows_after <- nrow(result$data$data)
  rows_before <- rows_after + as.integer(result$n_excluded)
  before_profile <- result$report_profile %||%
    build_report_profile(result$data$data)
  after_profile <- build_report_profile(result$data$data)

  model <- list(
    contract = list(name = "dcc-report", version = "1.0"),
    project = report_project(result, run),
    run = report_run(run),
    input = report_input(result, rows_before, rows_after),
    plan = report_plan(run),
    validation = report_validation(result),
    findings = findings,
    dispositions = dispositions,
    changes = changes,
    exclusions = exclusions,
    reconciliation = reconciliation,
    summaries = list(
      input_rows = as.integer(rows_before),
      output_rows = as.integer(rows_after),
      findings_total = as.integer(sum(findings$count)),
      changes_total = as.integer(nrow(changes)),
      excluded_total = as.integer(nrow(exclusions)),
      handled_total = as.integer(sum(reconciliation$handled)),
      unhandled_total = as.integer(sum(!reconciliation$handled)),
      missingness = report_missingness(before_profile, after_profile),
      distributions = rbind(
        report_profile_stage(before_profile$distributions, "before"),
        report_profile_stage(after_profile$distributions, "after")
      ),
      types = rbind(
        report_profile_stage(before_profile$types, "before"),
        report_profile_stage(after_profile$types, "after")
      )
    ),
    scoring = report_scoring(result),
    mapping = report_mapping(result),
    provenance = report_copy_table(dcc_provenance(result$data)),
    performance = report_performance(result),
    hashes = list(
      cleaned_data = hash_table(result$data$data),
      audit_log = hash_table(drop_volatile(result$audit)),
      input = as.character(result$data$meta$file_hash %||% NA_character_),
      ruleset = as.character(result$ruleset_hash %||% NA_character_)
    ),
    outputs = report_outputs(run),
    sensitivity = list(
      redacted_by_default = TRUE,
      examples_included = FALSE,
      raw_evidence_present = nrow(findings) > 0L
    )
  )

  validation <- dcc_validate_report_model(model)
  errors <- dcc_validation_errors(validation)
  if (nrow(errors)) {
    dcc_abort("Invalid normalized report model (", errors$code[1L], ").",
              class = "dcc_report_model_error")
  }
  structure(model, class = c("dcc_report_model", "list"))
}

#' Validate a normalized report model
#'
#' Checks the closed top-level contract and semantic reconciliation without
#' relying on an external JSON Schema runtime. It never changes `x`.
#'
#' @param x A report-model-like list.
#' @return A `dcc_validation` containing stable report contract codes.
#' @export
dcc_validate_report_model <- function(x) {
  issues <- list()
  add <- function(code, field, fix) {
    issues[[length(issues) + 1L]] <<-
      val_issue(code, "fail", field, fix = fix)
  }
  expected <- report_model_sections()
  if (!is.list(x)) {
    add("REPORT_TYPE_INVALID", "report_model", "Supply a named report model list.")
    return(new_validation(issues))
  }
  missing <- setdiff(expected, names(x))
  unknown <- setdiff(names(x), expected)
  if (length(missing)) {
    add("REPORT_SECTION_MISSING", paste(missing, collapse = ", "),
        "Restore every required report-model section.")
  }
  if (length(unknown)) {
    add("REPORT_SECTION_UNKNOWN", paste(unknown, collapse = ", "),
        "Remove fields outside the versioned report contract.")
  }
  if (length(missing) || length(unknown)) return(new_validation(issues))

  if (!identical(names(x), expected)) {
    add("REPORT_SECTION_ORDER_INVALID", "report_model",
        "Keep report-model sections in contract order.")
  }
  if (!identical(x$contract$name, "dcc-report") ||
      !identical(x$contract$version, "1.0")) {
    add("REPORT_CONTRACT_UNSUPPORTED", "contract",
        "Use dcc-report contract version 1.0.")
  }
  table_sections <- c("validation", "findings", "dispositions", "changes",
                      "exclusions", "reconciliation", "scoring", "mapping",
                      "provenance", "outputs")
  invalid_tables <- table_sections[!vapply(
    x[table_sections], is.data.frame, logical(1)
  )]
  if (length(invalid_tables)) {
    add("REPORT_TABLE_INVALID", paste(invalid_tables, collapse = ", "),
        "Use tabular values for every report table section.")
    return(new_validation(issues))
  }

  ids <- if ("finding_id" %in% names(x$findings)) {
    as.character(x$findings$finding_id)
  } else {
    character()
  }
  if (nrow(x$findings) &&
      (length(ids) != nrow(x$findings) || anyNA(ids) || any(!nzchar(ids)) ||
       anyDuplicated(ids))) {
    add("REPORT_FINDING_ID_INVALID", "findings.finding_id",
        "Use one unique, non-empty finding_id per finding.")
  }

  counts <- unlist(x$summaries[c(
    "input_rows", "output_rows", "findings_total", "changes_total",
    "excluded_total", "handled_total", "unhandled_total"
  )], use.names = FALSE)
  if (length(counts) != 7L || anyNA(counts) || !is.numeric(counts) ||
      any(counts < 0) || any(counts != as.integer(counts))) {
    add("REPORT_COUNT_INVALID", "summaries",
        "Use non-negative integer summary counts.")
  } else {
    finding_count <- if ("count" %in% names(x$findings)) {
      sum(x$findings$count, na.rm = TRUE)
    } else {
      NA_real_
    }
    expected_counts <- c(
      findings_total = finding_count,
      changes_total = nrow(x$changes),
      excluded_total = nrow(x$exclusions),
      handled_total = if ("handled" %in% names(x$reconciliation)) {
        sum(x$reconciliation$handled)
      } else NA_real_,
      unhandled_total = if ("handled" %in% names(x$reconciliation)) {
        sum(!x$reconciliation$handled)
      } else NA_real_,
      row_balance = x$summaries$output_rows + x$summaries$excluded_total
    )
    actual_counts <- c(
      findings_total = x$summaries$findings_total,
      changes_total = x$summaries$changes_total,
      excluded_total = x$summaries$excluded_total,
      handled_total = x$summaries$handled_total,
      unhandled_total = x$summaries$unhandled_total,
      row_balance = x$summaries$input_rows
    )
    if (anyNA(expected_counts) || !identical(
      as.numeric(actual_counts), as.numeric(expected_counts)
    )) {
      add("REPORT_RECONCILIATION_FAILED", "summaries",
          "Regenerate the model so all counts reconcile to source tables.")
    }
  }

  hash_values <- unlist(x$hashes, use.names = FALSE)
  present_hashes <- hash_values[!is.na(hash_values) & nzchar(hash_values)]
  if (length(present_hashes) &&
      any(!grepl("^[0-9a-f]{32}([0-9a-f]{32})?$", present_hashes))) {
    add("REPORT_HASH_INVALID", "hashes",
        "Use lowercase MD5 or SHA-256 hexadecimal hashes.")
  }
  timings <- unlist(x$performance, use.names = FALSE)
  if (!is.numeric(timings) || anyNA(timings) || any(timings < 0)) {
    add("REPORT_TIMING_INVALID", "performance",
        "Use non-negative numeric durations in seconds.")
  }
  new_validation(issues)
}

report_model_sections <- function() {
  c(
    "contract", "project", "run", "input", "plan", "validation",
    "findings", "dispositions", "changes", "exclusions", "reconciliation",
    "summaries", "scoring", "mapping", "provenance", "performance",
    "hashes", "outputs", "sensitivity"
  )
}

report_copy_table <- function(x) {
  as.data.frame(data.table::copy(data.table::as.data.table(x)),
                stringsAsFactors = FALSE)
}

report_project <- function(result, run) {
  project <- run$plan$project %||% list()
  list(
    project_id = as.character(project$project_id %||% "unspecified"),
    project_name = as.character(project$project_name %||% "DCC project"),
    language = as.character(project$language %||% "zh-CN")
  )
}

report_run <- function(run) {
  list(
    run_id = as.character(run$run_id %||% "standalone"),
    mode = as.character(run$mode %||% "standalone"),
    status = as.character(run$status %||% "success"),
    dcc_version = dcc_version_string()
  )
}

report_input <- function(result, rows_before, rows_after) {
  meta <- result$data$meta
  list(
    source = as.character(meta$source %||% NA_character_),
    format = as.character(meta$format %||% "data.frame"),
    encoding = as.character(meta$encoding %||% NA_character_),
    rows_before = as.integer(rows_before),
    rows_after = as.integer(rows_after),
    columns = as.integer(ncol(result$data$data))
  )
}

report_plan <- function(run) {
  plan <- run$plan
  if (is.null(plan)) {
    return(list(present = FALSE, template_version = NA_character_,
                outputs = list()))
  }
  list(
    present = TRUE,
    template_version = as.character(plan$project$template_version),
    outputs = lapply(seq_len(nrow(plan$outputs)), function(i) {
      as.list(plan$outputs[i, , drop = FALSE])
    })
  )
}

report_validation <- function(result) {
  report <- result$data$read_report
  value <- if (is.list(report) && is.data.frame(report$findings)) {
    report$findings
  } else {
    empty_validation()
  }
  report_copy_table(value)
}

report_scoring <- function(result) {
  data <- result$data$data
  columns <- grep("(^total_score$|_score$)", names(data), value = TRUE)
  if (!length(columns)) {
    return(data.frame(
      variable = character(), non_missing = integer(), missing = integer(),
      mean = numeric(), stringsAsFactors = FALSE
    ))
  }
  data.frame(
    variable = columns,
    non_missing = vapply(data[, columns, with = FALSE],
                         function(x) sum(!is.na(x)), integer(1)),
    missing = vapply(data[, columns, with = FALSE],
                     function(x) sum(is.na(x)), integer(1)),
    mean = vapply(data[, columns, with = FALSE],
                  function(x) mean(as.numeric(x), na.rm = TRUE), numeric(1)),
    stringsAsFactors = FALSE
  )
}

report_mapping <- function(result) {
  mapped <- Filter(function(x) identical(x$stage, "map_forms"),
                   result$data$provenance)
  if (!length(mapped)) {
    return(data.frame(
      stage = character(), map_hash = character(), masters = integer(),
      anchors = integer(), stringsAsFactors = FALSE
    ))
  }
  report_copy_table(data.frame(
    stage = "map_forms",
    map_hash = vapply(mapped, function(x) {
      as.character(x$hashes$form_map %||% NA_character_)
    }, character(1)),
    masters = vapply(mapped, function(x) {
      as.integer(x$counts$masters %||% 0L)
    }, integer(1)),
    anchors = vapply(mapped, function(x) {
      as.integer(x$counts$anchors %||% 0L)
    }, integer(1)),
    stringsAsFactors = FALSE
  ))
}

report_performance <- function(result) {
  records <- result$data$provenance
  seconds <- vapply(records, function(record) {
    start <- suppressWarnings(as.POSIXct(record$started_at, tz = "UTC"))
    end <- suppressWarnings(as.POSIXct(record$ended_at, tz = "UTC"))
    value <- as.numeric(difftime(end, start, units = "secs"))
    if (!is.finite(value)) 0 else max(0, value)
  }, numeric(1))
  stats::setNames(as.list(c(sum(seconds), seconds)),
                  c("total_seconds", paste0("stage_", seq_along(seconds),
                                             "_seconds")))
}

report_outputs <- function(run) {
  paths <- as.character(run$files %||% character())
  root <- as.character(run$run_dir %||% NA_character_)
  if (length(paths) && length(root) == 1L && !is.na(root) &&
      dir.exists(root)) {
    paths <- machine_relative_paths(paths, root)
  }
  data.frame(
    name = basename(paths), path = paths,
    status = rep("success", length(paths)), stringsAsFactors = FALSE
  )
}

build_report_profile <- function(data) {
  data <- data.table::as.data.table(data)
  missingness <- data.frame(
    variable = names(data),
    missing = vapply(data, function(x) sum(is.na(x)), integer(1)),
    rows = rep.int(nrow(data), ncol(data)),
    stringsAsFactors = FALSE
  )
  types <- data.frame(
    variable = names(data),
    class = vapply(data, function(x) paste(class(x), collapse = "/"),
                   character(1)),
    typeof = vapply(data, typeof, character(1)),
    rows = rep.int(nrow(data), ncol(data)),
    non_missing = vapply(data, function(x) sum(!is.na(x)), integer(1)),
    unique_non_missing = vapply(
      data, function(x) length(unique(x[!is.na(x)])), integer(1)
    ),
    stringsAsFactors = FALSE
  )
  distributions <- lapply(names(data), function(variable) {
    values <- as.character(data[[variable]])
    table <- data.table::data.table(
      variable = rep.int(variable, length(values)),
      value = values,
      missing = is.na(data[[variable]])
    )
    if (!nrow(table)) {
      table$count <- integer()
      return(as.data.frame(table))
    }
    out <- table[, list(count = .N), by = c("variable", "value", "missing")]
    as.data.frame(out[order(missing, value)], stringsAsFactors = FALSE)
  })
  distributions <- if (length(distributions)) {
    as.data.frame(data.table::rbindlist(distributions, use.names = TRUE))
  } else {
    data.frame(
      variable = character(), value = character(), missing = logical(),
      count = integer(), stringsAsFactors = FALSE
    )
  }
  list(
    rows = as.integer(nrow(data)),
    missingness = missingness,
    distributions = distributions,
    types = types
  )
}

report_profile_stage <- function(table, stage) {
  out <- as.data.frame(table, stringsAsFactors = FALSE)
  data.frame(stage = rep.int(stage, nrow(out)), out,
             stringsAsFactors = FALSE, check.names = FALSE)
}

report_missingness <- function(before, after) {
  variables <- union(before$missingness$variable, after$missingness$variable)
  before_idx <- match(variables, before$missingness$variable)
  after_idx <- match(variables, after$missingness$variable)
  data.frame(
    variable = variables,
    before_missing = before$missingness$missing[before_idx],
    before_rows = before$missingness$rows[before_idx],
    after_missing = after$missingness$missing[after_idx],
    after_rows = after$missingness$rows[after_idx],
    stringsAsFactors = FALSE
  )
}
