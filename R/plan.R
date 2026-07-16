plan_section_names <- function() {
  c("project", "source", "columns", "values", "missing", "multiselect",
    "rules", "actions", "outputs")
}

plan_table_contracts <- function() {
  list(
    columns = c("source_name", "name", "type", "role", "required", "label"),
    values = c("variable", "value", "label"),
    missing = c("variable", "source_value", "state"),
    multiselect = c("item", "layout", "source", "option", "delimiter"),
    rules = c("id", "type", "variable", "parameters", "severity"),
    actions = c("rule_id", "action", "parameters"),
    outputs = c("key", "value")
  )
}

empty_plan_table <- function(section) {
  fields <- plan_table_contracts()[[section]]
  out <- as.data.frame(stats::setNames(
    rep(list(character()), length(fields)), fields
  ),
                       stringsAsFactors = FALSE)
  data.table::as.data.table(out)
}

normalize_plan_table <- function(x, section) {
  if (is.null(x) || (is.data.frame(x) && !nrow(x) && !ncol(x))) {
    return(empty_plan_table(section))
  }
  if (!is.data.frame(x)) {
    dcc_abort("Plan section `", section, "` must be a data.frame.",
              class = "dcc_plan_error")
  }
  data.table::copy(data.table::as.data.table(x))
}

# Internal constructor shared by Excel, JSON, professional R callers, and
# agent integrations. Public callers normally use dcc_read_plan().
new_dcc_plan <- function(project, source, columns,
                         values = data.frame(), missing = data.frame(),
                         multiselect = data.frame(), rules = data.frame(),
                         actions = data.frame(), outputs = data.frame()) {
  structure(
    list(
      project = project,
      source = source,
      columns = normalize_plan_table(columns, "columns"),
      values = normalize_plan_table(values, "values"),
      missing = normalize_plan_table(missing, "missing"),
      multiselect = normalize_plan_table(multiselect, "multiselect"),
      rules = normalize_plan_table(rules, "rules"),
      actions = normalize_plan_table(actions, "actions"),
      outputs = normalize_plan_table(outputs, "outputs")
    ),
    class = "dcc_plan"
  )
}

plan_project_fields <- function() {
  c("template_version", "project_id", "project_name", "language",
    "created_by", "notes")
}

plan_source_fields <- function() {
  c("path", "format", "encoding", "sheet", "range", "member", "delimiter",
    "widths", "col_names", "catalog_file", "catalog_encoding",
    "compression", "max_uncompressed_bytes", "options_json")
}

plan_column_types <- function() {
  c("character", "integer", "double", "numeric", "logical", "date",
    "datetime")
}

plan_column_roles <- function() {
  c("id", "item", "score", "time", "group", "weight", "other")
}

plan_output_keys <- function() {
  c("report_language", "cleaned_format", "include_staff_report",
    "include_audit_report", "include_statistical_report",
    "include_machine_report", "statistical_table_format",
    "include_sensitive_examples")
}

plan_output_key_profiles <- function() {
  list(
    legacy = c("report_language", "cleaned_format", "include_staff_report",
               "include_audit_report"),
    current = c(
      "report_language", "cleaned_format", "include_staff_report",
      "include_statistical_report", "include_machine_report",
      "statistical_table_format", "include_sensitive_examples"
    )
  )
}

plan_add_unknown_fields <- function(add, values, allowed, prefix) {
  if (is.null(names(values))) return(invisible(NULL))
  for (field in setdiff(names(values), allowed)) {
    add("PLAN_UNKNOWN_FIELD", "fail", paste0(prefix, ".", field),
        fix = paste0("Remove `", field, "`; strict template 1.0 does not ",
                     "define it."))
  }
  invisible(NULL)
}

plan_check_table_contract <- function(add, x, section) {
  expected <- plan_table_contracts()[[section]]
  if (!is.data.frame(x)) {
    add("PLAN_SECTION_TYPE", "fail", section,
        fix = paste0("Make `", section, "` a table."))
    return(FALSE)
  }
  for (field in setdiff(names(x), expected)) {
    add("PLAN_UNKNOWN_FIELD", "fail", paste0(section, ".", field),
        fix = paste0("Remove column `", field, "` from sheet `", section,
                     "`."))
  }
  absent <- setdiff(expected, names(x))
  if (length(absent)) {
    add("PLAN_MISSING_FIELD", "fail", paste0(section, ".", absent[1L]),
        fix = paste0("Restore the strict template column(s): ",
                     paste(absent, collapse = ", "), "."))
  }
  !length(absent)
}

plan_bad_rows <- function(x) {
  which(is.na(x) | !nzchar(trimws(as.character(x))))
}

plan_json_object_ok <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(FALSE)
  value <- tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE),
                    error = function(e) NULL)
  is.list(value) && !is.null(names(value))
}

plan_source_path <- function(plan) {
  path <- as.character(plan$source$path %||% "")
  if (length(path) != 1L || is.na(path) || !nzchar(trimws(path))) return("")
  path <- path.expand(path)
  absolute <- grepl("^(/|[A-Za-z]:[/\\\\])", path)
  source <- plan_source_info(plan)
  if (!absolute && !is.null(source$path) && nzchar(source$path)) {
    path <- file.path(dirname(source$path), path)
  }
  path
}

plan_source_preflight <- function(plan) {
  source <- plan$source
  if (!is.list(source) || is.null(names(source))) return(empty_validation())
  format <- tolower(as.character(source$format %||% ""))
  if (length(format) != 1L || is.na(format) || !nzchar(format) ||
      !format %in% names(dcc_format_registry())) {
    return(empty_validation())
  }
  options_json <- as.character(source$options_json %||% "")
  if (nzchar(options_json) && !plan_json_object_ok(options_json)) {
    return(empty_validation())
  }
  path <- plan_source_path(plan)
  if (!nzchar(path)) return(empty_validation())
  options <- tryCatch(plan_import_options(plan), error = function(e) NULL)
  if (is.null(options)) return(empty_validation())
  spec <- structure(list(options = options), class = "dcc_import_spec")
  report <- tryCatch(
    dcc_get_adapter(format)$validator(path, spec),
    error = function(e) empty_validation()
  )
  if (!inherits(report, "dcc_validation") || !nrow(report)) return(report)
  report <- report[report$code != "IMPORT_ENCODING_REQUIRED"]
  if (!nrow(report)) return(empty_validation())
  report$field <- ifelse(
    report$field == "source", "source.path",
    paste0("source.", report$field)
  )
  report[]
}

#' Validate a strict DCC project plan
#'
#' Validates the common, versioned contract used by strict Excel workbooks and
#' JSON plans. Validation is read-only and returns stable issue codes suitable
#' for staff help pages and AI agents.
#'
#' @param x A `dcc_plan`, normally returned by `dcc_read_plan()`.
#' @return A `dcc_validation` table. Blocking rows have `severity == "fail"`.
#' @examples
#' p <- structure(list(), class = "dcc_plan")
#' dcc_validate_plan(p)
#' @export
dcc_validate_plan <- function(x) {
  issues <- list()
  add <- function(code, severity, field, rows = integer(), fix = "") {
    issues[[length(issues) + 1L]] <<-
      val_issue(code, severity, field, rows, fix)
  }
  finish <- function() locate_plan_validation(new_validation(issues), x)
  if (!inherits(x, "dcc_plan") || !is.list(x)) {
    dcc_abort("`x` must be a dcc_plan.", class = "dcc_type_error")
  }

  expected_sections <- plan_section_names()
  for (section in setdiff(names(x), expected_sections)) {
    add("PLAN_UNKNOWN_SECTION", "fail", section,
        fix = "Remove the section; strict template 1.0 has nine sections.")
  }
  absent_sections <- setdiff(expected_sections, names(x))
  for (section in absent_sections) {
    add("PLAN_MISSING_SECTION", "fail", section,
        fix = paste0("Restore the `", section, "` section."))
  }
  if (length(absent_sections)) return(finish())

  if (!is.list(x$project) || is.null(names(x$project))) {
    add("PLAN_SECTION_TYPE", "fail", "project",
        fix = "Use named project fields from template 1.0.")
  } else {
    plan_add_unknown_fields(add, x$project, plan_project_fields(), "project")
    for (field in c("template_version", "project_id", "project_name",
                    "language")) {
      if (is.null(x$project[[field]]) ||
          length(plan_bad_rows(x$project[[field]]))) {
        add("PLAN_PROJECT_REQUIRED", "fail", paste0("project.", field),
            fix = paste0("Fill in project field `", field, "`."))
      }
    }
    if (!identical(as.character(x$project$template_version %||% ""), "1.0")) {
      add("PLAN_TEMPLATE_VERSION", "fail", "project.template_version",
          fix = "Use the DCC strict template version 1.0.")
    }
    language <- as.character(x$project$language %||% "")
    if (!language %in% c("zh-CN", "en")) {
      add("PLAN_LANGUAGE", "fail", "project.language",
          fix = "Use `zh-CN` or `en`.")
    }
  }

  if (!is.list(x$source) || is.null(names(x$source))) {
    add("PLAN_SECTION_TYPE", "fail", "source",
        fix = "Use named source fields from template 1.0.")
  } else {
    plan_add_unknown_fields(add, x$source, plan_source_fields(), "source")
    for (field in c("path", "format")) {
      if (is.null(x$source[[field]]) || length(plan_bad_rows(x$source[[field]]))) {
        add("PLAN_SOURCE_REQUIRED", "fail", paste0("source.", field),
            fix = paste0("Fill in source field `", field, "`."))
      }
    }
    format <- tolower(as.character(x$source$format %||% ""))
    if (nzchar(format) && !format %in% names(dcc_format_registry())) {
      add("PLAN_SOURCE_FORMAT", "fail", "source.format",
          fix = paste0("Use one of: ",
                       paste(names(dcc_format_registry()), collapse = ", "), "."))
    }
    if (format %in% c("csv", "tsv", "txt", "fwf", "json", "jsonl") &&
        !nzchar(as.character(x$source$encoding %||% ""))) {
      add("PLAN_SOURCE_ENCODING", "fail", "source.encoding",
          fix = "Declare the text encoding, for example `UTF-8` or `GB18030`.")
    }
    options_json <- as.character(x$source$options_json %||% "")
    if (nzchar(options_json) && !plan_json_object_ok(options_json)) {
      add("PLAN_SOURCE_OPTIONS", "fail", "source.options_json",
          fix = "Use a JSON object such as `{\"sheet\":1}`.")
    }
  }

  valid_tables <- vapply(names(plan_table_contracts()), function(section) {
    plan_check_table_contract(add, x[[section]], section)
  }, logical(1))
  if (!all(valid_tables)) return(finish())

  columns <- x$columns
  for (field in c("source_name", "name", "type", "role")) {
    bad <- plan_bad_rows(columns[[field]])
    if (length(bad)) {
      add("PLAN_COLUMN_REQUIRED", "fail", paste0("columns.", field), bad,
          fix = paste0("Fill every `", field, "` cell."))
    }
  }
  for (field in c("source_name", "name")) {
    values <- as.character(columns[[field]])
    dup <- which(duplicated(values) | duplicated(values, fromLast = TRUE))
    if (length(dup)) {
      add("PLAN_COLUMN_DUPLICATE", "fail", paste0("columns.", field), dup,
          fix = paste0("Make `", field, "` values unique."))
    }
  }
  bad <- which(!tolower(as.character(columns$type)) %in% plan_column_types())
  if (length(bad)) {
    add("PLAN_COLUMN_TYPE", "fail", "columns.type", bad,
        fix = paste0("Use one of: ", paste(plan_column_types(), collapse = ", "),
                     "."))
  }
  bad <- which(!tolower(as.character(columns$role)) %in% plan_column_roles())
  if (length(bad)) {
    add("PLAN_COLUMN_ROLE", "fail", "columns.role", bad,
        fix = paste0("Use one of: ", paste(plan_column_roles(), collapse = ", "),
                     "."))
  }
  id_rows <- which(tolower(as.character(columns$role)) == "id")
  if (length(id_rows) > 1L) {
    add("PLAN_MULTIPLE_ID", "fail", "columns.role", id_rows,
        fix = "Declare at most one column with role `id`.")
  }
  required <- columns$required
  bad <- which(is.na(required) | !tolower(as.character(required)) %in%
                 c("true", "false"))
  if (length(bad)) {
    add("PLAN_COLUMN_REQUIRED_FLAG", "fail", "columns.required", bad,
        fix = "Use TRUE or FALSE.")
  }

  declared <- as.character(columns$name)
  for (section in c("values", "missing")) {
    tab <- x[[section]]
    bad <- which(!as.character(tab$variable) %in% declared)
    if (length(bad)) {
      add(paste0("PLAN_", toupper(section), "_VARIABLE"), "fail",
          paste0(section, ".variable"), bad,
          fix = "Use a canonical name declared on the columns sheet.")
    }
  }
  bad_states <- which(!as.character(x$missing$state) %in%
                        missing_state_levels())
  if (length(bad_states)) {
    add("PLAN_MISSING_STATE", "fail", "missing.state", bad_states,
        fix = paste0("Use one of: ",
                     paste(missing_state_levels(), collapse = ", "), "."))
  }
  bad_layout <- which(!as.character(x$multiselect$layout) %in%
                        c("delimited", "columns"))
  if (length(bad_layout)) {
    add("PLAN_MULTISELECT_LAYOUT", "fail", "multiselect.layout", bad_layout,
        fix = "Use `delimited` or `columns`.")
  }

  rules <- x$rules
  bad_ids <- plan_bad_rows(rules$id)
  if (length(bad_ids)) {
    add("PLAN_RULE_ID", "fail", "rules.id", bad_ids,
        fix = "Give every rule a non-empty id.")
  }
  dup_ids <- which(duplicated(rules$id) | duplicated(rules$id, fromLast = TRUE))
  if (length(dup_ids)) {
    add("PLAN_RULE_DUPLICATE", "fail", "rules.id", dup_ids,
        fix = "Make every rule id unique.")
  }
  bad <- which(!as.character(rules$type) %in% dcc_rule_types())
  if (length(bad)) {
    add("PLAN_RULE_TYPE", "fail", "rules.type", bad,
        fix = paste0("Use one of: ", paste(dcc_rule_types(), collapse = ", "),
                     "."))
  }
  bad <- which(!as.character(rules$severity) %in% c("info", "warn", "fail"))
  if (length(bad)) {
    add("PLAN_RULE_SEVERITY", "fail", "rules.severity", bad,
        fix = "Use `info`, `warn`, or `fail`.")
  }
  needs_variable <- rules$type %in% c("range", "set")
  bad <- which(needs_variable &
                 (!as.character(rules$variable) %in% declared))
  if (length(bad)) {
    add("PLAN_RULE_VARIABLE", "fail", "rules.variable", bad,
        fix = "Use a canonical name declared on the columns sheet.")
  }
  bad <- which(!vapply(as.character(rules$parameters), plan_json_object_ok,
                       logical(1)))
  if (length(bad)) {
    add("PLAN_RULE_PARAMETERS", "fail", "rules.parameters", bad,
        fix = "Use a JSON object, for example `{\"min\":0,\"max\":100}`.")
  }

  actions <- x$actions
  bad <- which(!as.character(actions$rule_id) %in% as.character(rules$id))
  if (length(bad)) {
    add("PLAN_ACTION_RULE", "fail", "actions.rule_id", bad,
        fix = "Use an id declared on the rules sheet.")
  }
  bad <- which(!as.character(actions$action) %in% dcc_action_types())
  if (length(bad)) {
    add("PLAN_ACTION_TYPE", "fail", "actions.action", bad,
        fix = paste0("Use one of: ", paste(dcc_action_types(), collapse = ", "),
                     "."))
  }
  bad <- which(!vapply(as.character(actions$parameters), plan_json_object_ok,
                       logical(1)))
  if (length(bad)) {
    add("PLAN_ACTION_PARAMETERS", "fail", "actions.parameters", bad,
        fix = "Use a JSON object; use `{}` when no parameters are needed.")
  }

  outputs <- x$outputs
  dup_keys <- which(duplicated(outputs$key) |
                      duplicated(outputs$key, fromLast = TRUE))
  if (length(dup_keys)) {
    add("PLAN_OUTPUT_DUPLICATE", "fail", "outputs.key", dup_keys,
        fix = "Use each output setting once.")
  }
  bad <- which(!as.character(outputs$key) %in% plan_output_keys())
  if (length(bad)) {
    add("PLAN_OUTPUT_KEY", "fail", "outputs.key", bad,
        fix = paste0("Use one of: ", paste(plan_output_keys(), collapse = ", "),
                     "."))
  }
  language_rows <- which(outputs$key == "report_language" &
                           !outputs$value %in% c("zh-CN", "en"))
  if (length(language_rows)) {
    add("PLAN_OUTPUT_LANGUAGE", "fail", "outputs.value", language_rows,
        fix = "Use `zh-CN` or `en`.")
  }
  format_rows <- which(outputs$key == "cleaned_format" &
                         !outputs$value %in% c("csv", "xlsx", "parquet"))
  if (length(format_rows)) {
    add("PLAN_OUTPUT_FORMAT", "fail", "outputs.value", format_rows,
        fix = "Use `csv`, `xlsx`, or `parquet`.")
  }
  logical_rows <- which(
    outputs$key %in% c(
      "include_staff_report", "include_audit_report",
      "include_statistical_report", "include_machine_report",
      "include_sensitive_examples"
    ) & !toupper(as.character(outputs$value)) %in% c("TRUE", "FALSE")
  )
  if (length(logical_rows)) {
    add("PLAN_OUTPUT_LOGICAL", "fail", "outputs.value", logical_rows,
        fix = "Use `TRUE` or `FALSE` for include settings.")
  }
  table_rows <- which(outputs$key == "statistical_table_format" &
                        !tolower(as.character(outputs$value)) %in%
                          c("csv", "parquet"))
  if (length(table_rows)) {
    add("PLAN_OUTPUT_TABLE_FORMAT", "fail", "outputs.value", table_rows,
        fix = "Use `csv` or `parquet` for statistical tables.")
  }

  source_preflight <- plan_source_preflight(x)
  if (nrow(source_preflight)) {
    for (i in seq_len(nrow(source_preflight))) {
      add(
        source_preflight$code[i], source_preflight$severity[i],
        source_preflight$field[i], source_preflight$rows[[i]],
        source_preflight$fix[i]
      )
    }
  }

  finish()
}

#' @export
print.dcc_plan <- function(x, ...) {
  cat(sprintf("<dcc_plan 1.0> %s: %d column(s), %d rule(s)\n",
              x$project$project_id %||% "<unnamed>", nrow(x$columns),
              nrow(x$rules)))
  invisible(x)
}
