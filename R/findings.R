#' The dcc_findings table
#'
#' A `dcc_findings` object is the structured violation list produced by
#' the Detect stage and consumed by the Execute stage. It is a
#' `data.table` with class `dcc_findings` and exactly these columns:
#' `record_id` (respondent/row identifier, character), `variable`
#' (affected variable, `NA` for record-level checks), `check_id` (stable
#' identifier of the rule or detector), `evidence` (human-readable
#' measured value), `severity` (`"info"`, `"warn"` or `"fail"`), and
#' `dimension` (quality dimension of the check).
#'
#' @param record_id Character vector (or coercible) of record ids.
#' @param variable Character vector of affected variables, or `NA`.
#' @param check_id Character vector of check identifiers.
#' @param evidence Character vector describing the measured evidence.
#' @param severity One of `"info"`, `"warn"`, `"fail"` (recycled).
#' @param dimension Quality dimension label (recycled).
#'
#' @return A `dcc_findings` object (also a `data.table`).
#' @export
dcc_findings <- function(record_id = character(), variable = NA_character_,
                         check_id = character(), evidence = character(),
                         severity = "warn", dimension = NA_character_) {
  # Size on record_id/evidence: check_id and severity are usually
  # scalars, and a zero-hit detector must yield zero findings.
  n <- max(length(record_id), length(evidence))
  if (n == 0L) {
    return(empty_findings())
  }
  severity <- as.character(severity)
  bad <- setdiff(unique(severity), c("info", "warn", "fail"))
  if (length(bad)) {
    dcc_abort("Invalid severity value(s): ", paste(bad, collapse = ", "),
              ". Use \"info\", \"warn\" or \"fail\".",
              class = "dcc_type_error")
  }
  out <- data.table::data.table(
    record_id = rep_len(as.character(record_id), n),
    variable = rep_len(as.character(variable), n),
    check_id = rep_len(as.character(check_id), n),
    evidence = rep_len(as.character(evidence), n),
    severity = rep_len(severity, n),
    dimension = rep_len(as.character(dimension), n)
  )
  data.table::setattr(out, "class",
                      c("dcc_findings", class(data.table::data.table())))
  out
}

empty_findings <- function() {
  out <- data.table::data.table(
    record_id = character(), variable = character(),
    check_id = character(), evidence = character(),
    severity = character(), dimension = character()
  )
  data.table::setattr(out, "class",
                      c("dcc_findings", class(data.table::data.table())))
  out
}

# rbind a list of dcc_findings preserving the class.
bind_findings <- function(lst) {
  lst <- Filter(function(x) !is.null(x) && nrow(x) > 0L, lst)
  if (!length(lst)) {
    return(empty_findings())
  }
  out <- data.table::rbindlist(lst, use.names = TRUE)
  data.table::setattr(out, "class",
                      c("dcc_findings", class(data.table::data.table())))
  out
}

#' @export
print.dcc_findings <- function(x, ...) {
  cat(sprintf("<dcc_findings> %d finding(s)\n", nrow(x)))
  if (nrow(x) > 0L) {
    tab <- table(x$check_id, x$severity)
    print(tab)
    cat("\n")
    NextMethod()
  }
  invisible(x)
}

# Resolve the data.table and record ids from a dcc_data or data.frame.
resolve_data <- function(x, id_var = NULL) {
  dt <- if (inherits(x, "dcc_data")) x$data else data.table::as.data.table(x)
  if (is.null(id_var)) {
    ids <- as.character(seq_len(nrow(dt)))
  } else {
    if (!id_var %in% names(dt)) {
      dcc_abort("`id_var` '", id_var, "' not found in data.",
                class = "dcc_type_error")
    }
    ids <- as.character(dt[[id_var]])
  }
  list(dt = dt, ids = ids)
}

# Validate that all item columns exist and return them as a matrix.
resolve_items <- function(dt, items) {
  missing_cols <- setdiff(items, names(dt))
  if (length(missing_cols)) {
    dcc_abort("Item column(s) not found: ",
              paste(missing_cols, collapse = ", "),
              class = "dcc_type_error")
  }
  as.matrix(dt[, items, with = FALSE])
}
