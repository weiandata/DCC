#' Level-0 structural diagnostics
#'
#' Runs Eurostat-style level-0 (structural) validation on a freshly read
#' table: dimensions, per-column type and missingness profile, duplicate
#' or empty column names, all-missing columns and rows, and encoding
#' confidence. Findings use the same shape as later detection stages
#' (`check_id` x `severity` x `evidence`) so the read report feeds the
#' same audit pipeline.
#'
#' @param data A `data.frame` or `data.table`.
#' @param meta Optional metadata list from [dcc_read()] (used for
#'   encoding-confidence findings).
#' @return A `dcc_read_report` object: a list with `n_rows`, `n_cols`,
#'   `columns` (per-column profile), and `findings` (L0 findings table).
#' @export
dcc_l0_diagnose <- function(data, meta = list()) {
  dt <- data.table::as.data.table(data)
  n_rows <- nrow(dt)
  n_cols <- ncol(dt)

  columns <- data.table::data.table(
    name = names(dt),
    class = vapply(dt, function(col) paste(class(col), collapse = "/"),
                   character(1)),
    n_missing = vapply(dt, function(col) sum(is.na(col)), integer(1)),
    n_unique = vapply(dt, function(col) data.table::uniqueN(col),
                      integer(1))
  )
  columns[, pct_missing := if (n_rows > 0L) n_missing / n_rows else NA_real_]

  findings <- list()
  add <- function(check_id, severity, variable, evidence) {
    findings[[length(findings) + 1L]] <<- data.table::data.table(
      check_id = check_id, severity = severity,
      variable = variable, evidence = evidence
    )
  }

  if (n_rows == 0L) {
    add("L0_EMPTY_TABLE", "fail", NA_character_, "0 rows")
  }
  if (n_cols == 1L) {
    add("L0_SINGLE_COLUMN", "warn", names(dt)[1],
        "only one column parsed; check delimiter/format")
  }

  dup <- names(dt)[duplicated(names(dt))]
  for (nm in unique(dup)) {
    add("L0_DUPLICATE_COLNAME", "fail", nm,
        sprintf("column name appears %d times", sum(names(dt) == nm)))
  }

  blank <- which(!nzchar(trimws(names(dt))) | grepl("^V\\d+$", names(dt)))
  for (i in blank) {
    add("L0_UNNAMED_COLUMN", "warn", names(dt)[i],
        sprintf("column %d has a blank or placeholder name", i))
  }

  all_na_cols <- columns[n_missing == n_rows & n_rows > 0L, name]
  for (nm in all_na_cols) {
    add("L0_ALL_MISSING_COLUMN", "warn", nm, "100% missing")
  }

  if (n_rows > 0L && n_cols > 0L) {
    n_empty_rows <- sum(rowSums(!is.na(dt)) == 0L)
    if (n_empty_rows > 0L) {
      add("L0_EMPTY_ROWS", "warn", NA_character_,
          sprintf("%d completely empty rows", n_empty_rows))
    }
  }

  conf <- meta$encoding_confidence
  if (!is.null(conf) && !is.na(conf) && conf < 0.8) {
    add("L0_ENCODING_UNCERTAIN", "warn", NA_character_,
        sprintf("detected %s with confidence %.2f; consider passing `encoding`",
                meta$encoding %||% "?", conf))
  }

  findings_dt <- if (length(findings)) {
    data.table::rbindlist(findings)
  } else {
    data.table::data.table(
      check_id = character(), severity = character(),
      variable = character(), evidence = character()
    )
  }

  structure(
    list(
      n_rows = n_rows,
      n_cols = n_cols,
      columns = columns[],
      findings = findings_dt,
      meta = meta
    ),
    class = "dcc_read_report"
  )
}

#' @export
print.dcc_read_report <- function(x, ...) {
  cat("<dcc_read_report>\n")
  cat(sprintf("  dimensions: %d rows x %d cols\n", x$n_rows, x$n_cols))
  if (!is.null(x$meta$encoding)) {
    conf <- x$meta$encoding_confidence
    conf_txt <- if (is.null(conf) || is.na(conf)) "" else
      sprintf(" (confidence %.2f)", conf)
    cat(sprintf("  encoding: %s%s\n", x$meta$encoding, conf_txt))
  }
  if (nrow(x$findings) == 0L) {
    cat("  L0 findings: none\n")
  } else {
    cat(sprintf("  L0 findings: %d\n", nrow(x$findings)))
    print(x$findings)
  }
  invisible(x)
}
