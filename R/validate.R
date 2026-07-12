#' Validate a rule set before it is used
#'
#' Checks a [dcc_rules()] rule set for structural problems -- unknown
#' types, missing required fields, duplicate or empty IDs -- and returns
#' a structured report. It never evaluates rules against data and never
#' changes anything.
#'
#' @param rules A `dcc_ruleset` from [dcc_rules()] (or the `rules`
#'   element of a `dcc_config`).
#' @return A `dcc_validation` object: a `data.table` with `code`,
#'   `severity`, `field`, `rows` (affected row indices, a list column),
#'   and `fix`.
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    min: 0", "    max: 100"), rf)
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   dcc_validate_rules(dcc_rules(rf))  # RULE_VAR_MISSING: no `variable`
#' }
#' @export
dcc_validate_rules <- function(rules) {
  if (!inherits(rules, "dcc_ruleset")) {
    dcc_abort("`rules` must be a dcc_ruleset from dcc_rules().",
              class = "dcc_type_error")
  }
  issues <- list()
  add <- function(code, severity, field, rows = integer(), fix = "") {
    issues[[length(issues) + 1L]] <<-
      val_issue(code, severity, field, rows, fix)
  }
  seen <- character()
  for (ch in rules$checks) {
    id <- as.character(ch$id %||% "")
    type <- ch$type %||% ""
    if (!nzchar(id)) {
      add("RULE_NO_ID", "fail", "id", fix = "Give every check an `id`.")
    }
    if (nzchar(id) && id %in% seen) {
      add("RULE_DUP_ID", "fail", id, fix = "Make every check `id` unique.")
    }
    seen <- c(seen, id)
    if (!type %in% dcc_rule_types()) {
      add("RULE_UNKNOWN_TYPE", "fail", id,
          fix = paste0("Use one of: ",
                       paste(dcc_rule_types(), collapse = ", "), "."))
      next
    }
    if (type %in% c("range", "set") && is.null(ch$variable)) {
      add("RULE_VAR_MISSING", "fail", id,
          fix = "Add a `variable` this check applies to.")
    }
    if (type == "range" && is.null(ch$min) && is.null(ch$max)) {
      add("RULE_RANGE_BOUNDS", "fail", id, fix = "Add a `min` and/or `max`.")
    }
    if (type == "set" && is.null(ch$values)) {
      add("RULE_SET_VALUES", "fail", id, fix = "Add the allowed `values`.")
    }
    if (type %in% c("missing_items", "straightlining") &&
        is.null(ch$items)) {
      add("RULE_ITEMS_MISSING", "fail", id, fix = "Add the `items` list.")
    }
    if (type == "response_time" && is.null(ch$time_var)) {
      add("RULE_TIMEVAR_MISSING", "fail", id, fix = "Add a `time_var`.")
    }
    if (type == "trap_items" && is.null(ch$traps)) {
      add("RULE_TRAPS_MISSING", "fail", id, fix = "Add the `traps` map.")
    }
    if (type == "score_anomaly" && is.null(ch$score_var)) {
      add("RULE_SCOREVAR_MISSING", "fail", id, fix = "Add a `score_var`.")
    }
    sev <- ch$severity %||% "warn"
    if (!sev %in% c("info", "warn", "fail")) {
      add("RULE_BAD_SEVERITY", "warn", id,
          fix = "Use \"info\", \"warn\" or \"fail\".")
    }
  }
  new_validation(issues)
}

#' Validate data against a rule set before detection
#'
#' Checks that a dataset can carry a cleaning run: the record-id column
#' is present, non-missing, and unique, and every variable a rule
#' references exists. It never changes the data.
#'
#' @param data A `dcc_data` or data.frame.
#' @param rules Optional `dcc_ruleset`; when supplied, referenced
#'   variables are checked against the data columns.
#' @param id_var Optional record-id column to check for presence,
#'   missingness, and duplication.
#' @return A `dcc_validation` object (see [dcc_validate_rules()]).
#' @examples
#' df <- data.frame(sid = c("S1", "S1", "S2"), score = c(50, 150, 70))
#' dcc_validate_data(df, id_var = "sid")  # DATA_DUP_ID on rows 1,2
#' @export
dcc_validate_data <- function(data, rules = NULL, id_var = NULL) {
  dt <- if (inherits(data, "dcc_data")) {
    data$data
  } else {
    data.table::as.data.table(data)
  }
  issues <- list()
  add <- function(code, severity, field, rows = integer(), fix = "") {
    issues[[length(issues) + 1L]] <<-
      val_issue(code, severity, field, rows, fix)
  }
  if (!is.null(id_var)) {
    if (!id_var %in% names(dt)) {
      add("DATA_NO_ID_VAR", "fail", id_var,
          fix = "Choose a record-id column that exists in the data.")
    } else {
      ids <- as.character(dt[[id_var]])
      na_rows <- which(is.na(ids) | !nzchar(ids))
      if (length(na_rows)) {
        add("DATA_NA_ID", "fail", id_var, na_rows,
            fix = "Fill in the missing record ids.")
      }
      dup_rows <- which(duplicated(ids) | duplicated(ids, fromLast = TRUE))
      if (length(dup_rows)) {
        add("DATA_DUP_ID", "fail", id_var, dup_rows,
            fix = "Make every record id unique.")
      }
    }
  }
  if (!is.null(rules)) {
    if (!inherits(rules, "dcc_ruleset")) {
      dcc_abort("`rules` must be a dcc_ruleset from dcc_rules().",
                class = "dcc_type_error")
    }
    for (ch in rules$checks) {
      vars <- unique(c(ch$variable, ch$time_var, ch$score_var,
                       unlist(ch$items), names(ch$traps)))
      absent <- setdiff(vars, names(dt))
      if (length(absent)) {
        add("DATA_VAR_ABSENT", "fail", paste(absent, collapse = ", "),
            fix = paste0("Check '", ch$id %||% "?",
                         "' references column(s) missing from the data."))
      }
    }
  }
  new_validation(issues)
}

#' Run every validator over a dataset and rule set
#'
#' Convenience wrapper: runs [dcc_validate_rules()] and
#' [dcc_validate_data()] and merges their reports.
#'
#' @param data A `dcc_data` or data.frame.
#' @param rules A `dcc_ruleset` from [dcc_rules()].
#' @param id_var Optional record-id column.
#' @return A combined `dcc_validation` object.
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    variable: score", "    min: 0", "    max: 100"), rf)
#' df <- data.frame(sid = c("S1", "S2"), score = c(50, 70))
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   dcc_doctor(df, dcc_rules(rf), id_var = "sid")
#' }
#' @export
dcc_doctor <- function(data, rules, id_var = NULL) {
  combined <- data.table::rbindlist(list(
    dcc_validate_rules(rules),
    dcc_validate_data(data, rules, id_var)
  ))
  data.table::setattr(combined, "class",
                      c("dcc_validation", class(data.table::data.table())))
  combined[]
}

#' The failing issues of a validation report
#'
#' @param x A `dcc_validation` object.
#' @return The subset of `x` with `severity == "fail"`.
#' @examples
#' df <- data.frame(sid = c("S1", "S1"), score = c(50, 70))
#' dcc_validation_errors(dcc_validate_data(df, id_var = "sid"))
#' @export
dcc_validation_errors <- function(x) {
  if (!inherits(x, "dcc_validation")) {
    dcc_abort("`x` must be a dcc_validation report.", class = "dcc_type_error")
  }
  x[x$severity == "fail"]
}

# One-row validation issue as a data.table with a list-column of rows.
val_issue <- function(code, severity, field, rows = integer(), fix = "") {
  data.table::data.table(
    code = code, severity = severity, field = field,
    rows = list(rows), fix = fix
  )
}

empty_validation <- function() {
  out <- data.table::data.table(
    code = character(), severity = character(), field = character(),
    rows = list(), fix = character()
  )
  data.table::setattr(out, "class",
                      c("dcc_validation", class(data.table::data.table())))
  out
}

new_validation <- function(issues) {
  if (!length(issues)) {
    return(empty_validation())
  }
  out <- data.table::rbindlist(issues)
  data.table::setattr(out, "class",
                      c("dcc_validation", class(data.table::data.table())))
  out
}

#' @export
print.dcc_validation <- function(x, ...) {
  if (!nrow(x)) {
    cat("<dcc_validation> no issues\n")
    return(invisible(x))
  }
  cat(sprintf("<dcc_validation> %d issue(s)\n", nrow(x)))
  for (i in seq_len(nrow(x))) {
    rows <- x$rows[[i]]
    loc <- if (length(rows)) {
      paste0(" rows ", paste(utils::head(rows, 5L), collapse = ","),
             if (length(rows) > 5L) "..." else "")
    } else {
      ""
    }
    cat(sprintf("  [%s] %s (%s)%s: %s\n",
                x$severity[i], x$code[i], x$field[i], loc, x$fix[i]))
  }
  invisible(x)
}
