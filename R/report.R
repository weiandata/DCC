#' Generate a cleaning report (Report stage)
#'
#' Renders a self-contained HTML report from a `dcc_result`, in two
#' audiences (design decision: dual-layer reporting):
#'
#' * `"summary"` -- management layer: findings by quality dimension and
#'   severity, change volumes by action, exclusion counts, provenance
#'   chain and rule/key hashes.
#' * `"audit"` -- audit layer: everything in the summary plus the full
#'   findings table (with evidence), the findings-to-changes
#'   reconciliation ([dcc_reconcile()]) and the cell-level change log
#'   (both capped at `max_rows` rows in HTML; the complete log is
#'   exported with [dcc_export_log()]).
#'
#' The HTML is generated directly (no pandoc/rmarkdown dependency) so
#' reports render identically on CI and analyst machines.
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @param path Output `.html` file path, or `NULL` to only return the
#'   HTML string.
#' @param audience `"summary"` (default) or `"audit"`.
#' @param max_rows Maximum audit-log rows embedded in the HTML
#'   (default 1000).
#' @return The HTML document as a character string, invisibly. Written
#'   to `path` when given.
#' @export
dcc_report <- function(x, path = NULL, audience = c("summary", "audit"),
                       max_rows = 1000L) {
  stopifnot(inherits(x, "dcc_result"))
  audience <- match.arg(audience)

  f <- x$findings
  log <- x$audit
  parts <- character()
  add <- function(...) parts <<- c(parts, paste0(...))

  add("<!DOCTYPE html><html><head><meta charset='utf-8'>")
  add("<title>DCC cleaning report</title>")
  add("<style>body{font-family:sans-serif;margin:2em;}",
      "table{border-collapse:collapse;margin:1em 0;}",
      "td,th{border:1px solid #999;padding:4px 8px;text-align:left;}",
      "th{background:#eee;}h2{margin-top:1.5em;}",
      ".meta{color:#555;font-size:0.9em;}</style></head><body>")
  add("<h1>DCC cleaning report (", html_escape(audience), ")</h1>")
  add("<p class='meta'>generated ", html_escape(dcc_timestamp()),
      " | DCC ", html_escape(dcc_version_string()),
      " | ruleset hash ", html_escape(x$ruleset_hash %||% "n/a"), "</p>")

  add("<h2>Overview</h2>")
  add(html_table(data.table::data.table(
    metric = c("findings", "changes logged", "records excluded",
               "cleaned rows", "cleaned columns"),
    value = c(nrow(f), nrow(log), x$n_excluded,
              nrow(x$data$data), ncol(x$data$data))
  )))

  add("<h2>Findings by quality dimension and severity</h2>")
  if (nrow(f)) {
    dim_tab <- data.table::as.data.table(f)[
      , list(n = .N), by = c("dimension", "severity")]
    add(html_table(dim_tab[order(dimension, severity)]))
  } else {
    add("<p>No findings.</p>")
  }

  add("<h2>Changes by action</h2>")
  if (nrow(log)) {
    add(html_table(log[, list(n = .N), by = c("action", "check_id")]))
  } else {
    add("<p>No changes.</p>")
  }

  add("<h2>Provenance</h2>")
  prov <- dcc_provenance(x$data)
  add(html_table(prov[, c("stage", "timestamp", "dcc_version"),
                      with = FALSE]))

  if (audience == "audit") {
    add("<h2>Findings</h2>")
    if (nrow(f)) {
      shown_f <- utils::head(data.table::as.data.table(f), max_rows)
      if (nrow(f) > nrow(shown_f)) {
        add("<p class='meta'>showing first ", nrow(shown_f), " of ",
            nrow(f), " findings.</p>")
      }
      add(html_table(shown_f))
    } else {
      add("<p>No findings.</p>")
    }
    add("<h2>Findings-to-changes reconciliation</h2>")
    rec <- dcc_reconcile(x)
    add("<p>", sum(rec$handled), " of ", nrow(rec),
        " finding(s) handled; unreconciled changes: ",
        attr(rec, "unreconciled_changes"), ".</p>")
    add(html_table(rec[, list(n = .N),
                       by = c("check_id", "action", "handled")]))
    add("<h2>Cell-level change log</h2>")
    shown <- utils::head(log, max_rows)
    if (nrow(log) > nrow(shown)) {
      add("<p class='meta'>showing first ", nrow(shown), " of ",
          nrow(log), " rows; export the full log with dcc_export_log().",
          "</p>")
    }
    add(html_table(shown))
  }

  add("</body></html>")
  html <- paste(parts, collapse = "\n")
  if (!is.null(path)) {
    writeLines(html, path, useBytes = TRUE)
  }
  invisible(html)
}

html_escape <- function(s) {
  s <- gsub("&", "&amp;", as.character(s), fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  gsub(">", "&gt;", s, fixed = TRUE)
}

html_table <- function(dt) {
  dt <- data.table::as.data.table(dt)
  head_row <- paste0("<tr>", paste0("<th>", html_escape(names(dt)),
                                    "</th>", collapse = ""), "</tr>")
  body <- vapply(seq_len(nrow(dt)), function(i) {
    cells <- vapply(names(dt), function(cn) {
      v <- dt[[cn]][i]
      paste0("<td>", html_escape(if (is.na(v)) "" else v), "</td>")
    }, character(1))
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, character(1))
  paste0("<table>", head_row, paste(body, collapse = ""), "</table>")
}

#' Reconcile findings against logged changes (closed loop)
#'
#' Verifies DCC's closed-loop guarantee from both directions: every
#' finding should have at least one audit-log row (handled), and every
#' audit-log row must trace back to a finding (no unexplained changes).
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @return The findings table extended with `action` (the executed
#'   action, `NA` if none) and `handled` (logical). The number of audit
#'   rows that do not match any finding is attached as the
#'   `unreconciled_changes` attribute (must be 0 in a healthy
#'   pipeline).
#' @export
dcc_reconcile <- function(x) {
  stopifnot(inherits(x, "dcc_result"))
  f <- data.table::copy(data.table::as.data.table(x$findings))
  log <- x$audit
  f[, `:=`(action = NA_character_, handled = FALSE)]
  if (nrow(f) && nrow(log)) {
    keyed <- log[, list(action = action[1L]),
                 by = c("record_id", "check_id")]
    for (i in seq_len(nrow(f))) {
      hit <- keyed[
        (is.na(record_id) & is.na(f$record_id[i]) |
           (!is.na(record_id) & !is.na(f$record_id[i]) &
              record_id == f$record_id[i])) &
          check_id == f$check_id[i]]
      if (nrow(hit)) {
        data.table::set(f, i = i, j = "action", value = hit$action[1L])
        data.table::set(f, i = i, j = "handled", value = TRUE)
      }
    }
  }
  unrec <- 0L
  if (nrow(log)) {
    fk <- paste(x$findings$record_id, x$findings$check_id, sep = "\r")
    lk <- paste(log$record_id, log$check_id, sep = "\r")
    unrec <- sum(!lk %in% fk)
  }
  data.table::setattr(f, "unreconciled_changes", unrec)
  f[]
}

#' Trace the cleaning history of a record or cell
#'
#' Reverse lookup from the cleaned data back through the pipeline: all
#' findings and all logged changes for a record, optionally narrowed to
#' one variable (i.e. one cell).
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @param record_id Record identifier (as used in the findings).
#' @param variable Optional variable name to narrow the trace to a
#'   single cell.
#' @return A `dcc_trace` object: list with `record_id`, `variable`,
#'   `findings` (matching findings rows) and `changes` (matching audit
#'   rows).
#' @export
dcc_trace <- function(x, record_id, variable = NULL) {
  stopifnot(inherits(x, "dcc_result"))
  rid <- as.character(record_id)
  f <- data.table::as.data.table(x$findings)
  f <- f[!is.na(f$record_id) & f$record_id == rid, ]
  log <- x$audit[!is.na(x$audit$record_id) & x$audit$record_id == rid, ]
  if (!is.null(variable)) {
    f <- f[!is.na(f$variable) & f$variable == variable, ]
    log <- log[!is.na(log$variable) & log$variable == variable, ]
  }
  structure(
    list(record_id = rid, variable = variable,
         findings = f, changes = log),
    class = "dcc_trace"
  )
}

#' @export
print.dcc_trace <- function(x, ...) {
  cat(sprintf("<dcc_trace> record '%s'%s\n", x$record_id,
              if (is.null(x$variable)) "" else
                paste0(", variable '", x$variable, "'")))
  cat(sprintf("  findings: %d\n", nrow(x$findings)))
  if (nrow(x$findings)) {
    print(x$findings[, c("check_id", "variable", "evidence", "severity"),
                     with = FALSE])
  }
  cat(sprintf("  changes: %d\n", nrow(x$changes)))
  if (nrow(x$changes)) {
    print(x$changes[, c("variable", "old_value", "new_value", "action",
                        "check_id", "timestamp"), with = FALSE])
  }
  invisible(x)
}
