#' The dcc_data container
#'
#' A `dcc_data` object bundles the dataset with its metadata, the level-0
#' read report, and an append-only provenance chain. Every DCC stage
#' (detect, execute, report) receives and returns this container; stages
#' append to the provenance chain and never rewrite it (raw data is
#' immutable -- cleaning produces new versions).
#'
#' @param data A `data.frame` or `data.table`.
#' @param meta Named list of source metadata (see [dcc_read()]).
#' @param read_report A `dcc_read_report` object, or `NULL`.
#' @param provenance List of provenance records; normally created
#'   internally.
#' @param dictionary Canonical variable dictionary with unique `name` values.
#' @param missing_states Cell-level missing-state table using DCC's declared
#'   missing-state vocabulary.
#' @param import_spec The `dcc_import_spec` that produced the canonical data,
#'   or `NULL` for data created directly in R.
#'
#' @return An object of class `dcc_data`: a list with elements `data`
#'   (a `data.table`), `meta`, `read_report`, and `provenance`.
#' @export
dcc_data <- function(data, meta = list(), read_report = NULL,
                     provenance = NULL, dictionary = NULL,
                     missing_states = NULL, import_spec = NULL) {
  if (!is.data.frame(data)) {
    dcc_abort("`data` must be a data.frame or data.table, got ",
              paste(class(data), collapse = "/"), ".",
              class = "dcc_type_error")
  }
  dt <- data.table::as.data.table(data)
  dictionary <- normalize_dictionary(dictionary)
  missing_states <- normalize_missing_states(missing_states)
  if (!is.null(import_spec) && !inherits(import_spec, "dcc_import_spec")) {
    dcc_abort("`import_spec` must be a dcc_import_spec or NULL.",
              class = "dcc_import_error")
  }

  if (is.null(provenance)) {
    provenance <- list(new_provenance_record(
      stage = "create",
      details = list(n_rows = nrow(dt), n_cols = ncol(dt)),
      counts = list(rows = nrow(dt), columns = ncol(dt))
    ))
  }

  structure(
    list(
      data = dt,
      meta = meta,
      read_report = read_report,
      provenance = provenance,
      dictionary = dictionary,
      missing_states = missing_states,
      import_spec = import_spec
    ),
    class = "dcc_data"
  )
}

new_provenance_record <- function(stage, details = list(),
                                  started_at = dcc_timestamp(),
                                  ended_at = dcc_timestamp(),
                                  outcome = "success", hashes = list(),
                                  counts = list()) {
  list(
    stage = stage,
    started_at = started_at,
    ended_at = ended_at,
    outcome = outcome,
    dcc_version = dcc_version_string(),
    hashes = hashes,
    counts = counts,
    details = details
  )
}

append_provenance <- function(x, stage, details = list(), hashes = list(),
                              counts = list(), outcome = "success",
                              started_at = dcc_timestamp(),
                              ended_at = dcc_timestamp()) {
  stopifnot(inherits(x, "dcc_data"))
  x$provenance <- c(x$provenance, list(new_provenance_record(
    stage, details, started_at = started_at, ended_at = ended_at,
    outcome = outcome, hashes = hashes, counts = counts
  )))
  x
}

#' Provenance chain of a dcc_data object
#'
#' @param x A `dcc_data` object.
#' @return A `data.table` with one row per provenance record: `stage`, stage
#'   boundaries, outcome, DCC version, and list-columns for hashes, counts, and
#'   details.
#' @export
dcc_provenance <- function(x) {
  stopifnot(inherits(x, "dcc_data"))
  data.table::rbindlist(lapply(x$provenance, function(rec) {
    started_at <- rec$started_at %||% rec$timestamp
    ended_at <- rec$ended_at %||% started_at
    data.table::data.table(
      stage = rec$stage,
      started_at = started_at,
      ended_at = ended_at,
      outcome = rec$outcome %||% "success",
      dcc_version = rec$dcc_version,
      hashes = list(rec$hashes %||% list()),
      counts = list(rec$counts %||% list()),
      details = list(rec$details)
    )
  }))
}

#' Read report of a dcc_data object
#'
#' @param x A `dcc_data` object.
#' @return The `dcc_read_report` attached at read time, or `NULL`.
#' @export
dcc_read_report <- function(x) {
  stopifnot(inherits(x, "dcc_data"))
  x$read_report
}

#' @export
dim.dcc_data <- function(x) dim(x$data)

#' @export
as.data.frame.dcc_data <- function(x, row.names = NULL, optional = FALSE,
                                   ...) {
  as.data.frame(x$data, row.names = row.names, optional = optional, ...)
}

#' @export
print.dcc_data <- function(x, ...) {
  cat("<dcc_data>\n")
  cat(sprintf("  rows: %d  cols: %d\n", nrow(x$data), ncol(x$data)))
  if (!is.null(x$meta$source)) {
    cat(sprintf("  source: %s (%s, %s)\n",
                x$meta$source,
                x$meta$format %||% "?",
                x$meta$encoding %||% "?"))
  }
  stages <- vapply(x$provenance, function(r) r$stage, character(1))
  cat(sprintf("  provenance: %s\n", paste(stages, collapse = " -> ")))
  n_findings <- if (!is.null(x$read_report)) {
    nrow(x$read_report$findings)
  } else {
    NA_integer_
  }
  if (!is.na(n_findings)) {
    cat(sprintf("  L0 findings: %d\n", n_findings))
  }
  cat("  data preview:\n")
  print(utils::head(x$data, 4L))
  invisible(x)
}
