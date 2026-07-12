#' Execute actions on detected findings (Execute stage)
#'
#' Applies declarative actions to the findings produced by the Detect
#' stage, following the closed-loop rule: only cells and records named
#' in the findings list are ever touched, and every change is logged at
#' cell level. The input is never modified; a new dataset version is
#' produced.
#'
#' Supported actions (mapped to `check_id`s via `actions`):
#'
#' * `"exclude"` -- remove the record from the cleaned dataset (the
#'   removal is logged; nothing is deleted from the audit trail).
#' * `"set_na"` -- set the finding's (record, variable) cell to `NA`.
#' * `"flag"` -- keep the data unchanged but log the finding as
#'   reviewed-and-kept.
#' * `list(action = "recode", map = c(old = new, ...))` -- replace the
#'   cell value using the map (values compared as character).
#'
#' Findings whose `check_id` has no entry in `actions` receive
#' `default` (`"flag"` unless overridden), so no finding silently
#' disappears.
#'
#' @param x A [dcc_data()] object or data.frame.
#' @param findings A [dcc_findings()] table from the Detect stage.
#' @param actions Named list mapping `check_id`s to actions (see
#'   Details).
#' @param id_var Name of the record-id column matching the findings'
#'   `record_id`, or `NULL` for row numbers.
#' @param default Action for findings without an `actions` entry
#'   (default `"flag"`).
#' @param ruleset_hash Optional rule-file hash to stamp into the audit
#'   log (taken from the findings' `dcc_data` attribute when available).
#' @return A `dcc_result` object: list with `data` (the new
#'   [dcc_data()] version), `audit` (the cell-level audit log), and
#'   `n_excluded`. Accessors: [dcc_audit_log()], [dcc_cleaned()].
#' @export
dcc_execute <- function(x, findings, actions = list(), id_var = NULL,
                        default = "flag", ruleset_hash = NULL) {
  if (!inherits(findings, "dcc_findings")) {
    dcc_abort("`findings` must be a dcc_findings table from dcc_detect() ",
              "or a detect_*() function.", class = "dcc_type_error")
  }
  if (is.null(ruleset_hash)) {
    src <- attr(findings, "dcc_data", exact = TRUE)
    if (!is.null(src)) {
      det <- Filter(function(p) p$stage == "detect", src$provenance)
      if (length(det)) {
        ruleset_hash <- det[[length(det)]]$details$ruleset_hash
      }
    }
  }
  r <- resolve_data(x, id_var)
  dt <- data.table::copy(r$dt)
  row_of <- split(seq_len(nrow(dt)), r$ids)

  audit <- list()
  excluded_rows <- integer()
  log_change <- function(record_id, variable, old, new, action, check_id,
                         method) {
    audit[[length(audit) + 1L]] <<- data.table::data.table(
      record_id = record_id,
      variable = variable %||% NA_character_,
      old_value = as.character(old),
      new_value = as.character(new),
      action = action,
      check_id = check_id,
      method = method,
      timestamp = dcc_timestamp(),
      dcc_version = dcc_version_string(),
      ruleset_hash = ruleset_hash %||% NA_character_,
      keyfile_hash = NA_character_
    )
  }

  # Vector indexing instead of per-row data.table subsetting: the loop
  # must stay cheap when findings run into the hundreds of thousands.
  f_rid <- findings$record_id
  f_var <- findings$variable
  f_chk <- findings$check_id
  for (i in seq_len(nrow(findings))) {
    act <- actions[[f_chk[i]]] %||% default
    act_name <- if (is.list(act)) act$action %||% "" else act
    if (is.na(f_rid[i])) {
      # Record-less findings (e.g. group-level) can only be flagged.
      rows <- integer()
    } else {
      rows <- row_of[[f_rid[i]]]
      if (is.null(rows)) {
        dcc_abort("Finding record_id '", f_rid[i], "' not found in ",
                  "data (check `id_var`).", class = "dcc_execute_error")
      }
    }
    switch(act_name,
      exclude = {
        excluded_rows <- union(excluded_rows, rows)
        log_change(f_rid[i], NA_character_, NA, NA, "exclude",
                   f_chk[i], "record excluded from cleaned dataset")
      },
      set_na = {
        v <- f_var[i]
        if (is.na(v) || !v %in% names(dt)) {
          dcc_abort("Finding for check '", f_chk[i], "' has no usable ",
                    "`variable`; set_na needs a cell to clear.",
                    class = "dcc_execute_error")
        }
        old <- dt[[v]][rows]
        data.table::set(dt, i = rows, j = v, value = NA)
        log_change(rep(f_rid[i], length(rows)), v, old, NA, "set_na",
                   f_chk[i], "cell set to NA")
      },
      recode = {
        v <- f_var[i]
        map <- act$map
        if (is.na(v) || !v %in% names(dt)) {
          dcc_abort("Finding for check '", f_chk[i], "' has no usable ",
                    "`variable`; recode needs a cell.",
                    class = "dcc_execute_error")
        }
        if (is.null(map) || is.null(names(map))) {
          dcc_abort("recode action for check '", f_chk[i], "' needs a ",
                    "named `map`.", class = "dcc_execute_error")
        }
        old <- dt[[v]][rows]
        key <- as.character(old)
        hitmap <- key %in% names(map)
        if (any(hitmap)) {
          new_vals <- old
          new_raw <- unname(map[key[hitmap]])
          new_vals[hitmap] <- methods::as(new_raw, class(dt[[v]])[1])
          data.table::set(dt, i = rows, j = v, value = new_vals)
          log_change(rep(f_rid[i], sum(hitmap)), v, old[hitmap],
                     new_raw, "recode", f_chk[i],
                     "cell recoded via action map")
        }
      },
      flag = {
        log_change(f_rid[i], f_var[i], NA, NA, "flag", f_chk[i],
                   "reviewed and kept (no data change)")
      },
      dcc_abort("Unknown action '", act_name, "' for check '",
                f_chk[i], "'.", class = "dcc_execute_error")
    )
  }

  keep <- setdiff(seq_len(nrow(dt)), excluded_rows)
  cleaned_dt <- dt[keep]

  audit_dt <- if (length(audit)) {
    data.table::rbindlist(audit)
  } else {
    empty_audit_log()
  }

  base <- if (inherits(x, "dcc_data")) x else dcc_data(r$dt)
  out_data <- dcc_data(
    cleaned_dt,
    meta = base$meta,
    read_report = base$read_report,
    provenance = c(base$provenance, list(new_provenance_record(
      stage = "execute",
      details = list(
        n_findings = nrow(findings),
        n_changes = nrow(audit_dt),
        n_excluded = length(excluded_rows),
        ruleset_hash = ruleset_hash %||% NA_character_
      )
    )))
  )

  structure(
    list(
      data = out_data,
      audit = audit_dt,
      n_excluded = length(excluded_rows),
      findings = findings,
      actions = actions,
      id_var = id_var,
      default = default,
      ruleset_hash = ruleset_hash %||% NA_character_
    ),
    class = "dcc_result"
  )
}

empty_audit_log <- function() {
  data.table::data.table(
    record_id = character(), variable = character(),
    old_value = character(), new_value = character(),
    action = character(), check_id = character(), method = character(),
    timestamp = character(), dcc_version = character(),
    ruleset_hash = character(), keyfile_hash = character()
  )
}

#' Audit log of a dcc_result
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @return The cell-level audit log as a `data.table`: `record_id`,
#'   `variable`, `old_value`, `new_value`, `action`, `check_id`,
#'   `method`, `timestamp`, `dcc_version`, `ruleset_hash`,
#'   `keyfile_hash`.
#' @export
dcc_audit_log <- function(x) {
  stopifnot(inherits(x, "dcc_result"))
  x$audit
}

#' Cleaned dataset of a dcc_result
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @return The new [dcc_data()] version produced by the Execute stage.
#' @export
dcc_cleaned <- function(x) {
  stopifnot(inherits(x, "dcc_result"))
  x$data
}

#' Export an audit log for external auditors
#'
#' Writes the audit log as Parquet (default; schema-typed and compact)
#' or CSV (plain file for auditors without Parquet tooling).
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @param path Output file path.
#' @param format `"parquet"` (default, requires the `arrow` package) or
#'   `"csv"`.
#' @return `path`, invisibly.
#' @export
dcc_export_log <- function(x, path, format = c("parquet", "csv")) {
  format <- match.arg(format)
  log <- dcc_audit_log(x)
  if (format == "parquet") {
    dcc_require("arrow", "write Parquet audit logs")
    arrow::write_parquet(log, path)
  } else {
    data.table::fwrite(log, path)
  }
  invisible(path)
}

#' @export
print.dcc_result <- function(x, ...) {
  cat("<dcc_result>\n")
  cat(sprintf("  cleaned data: %d rows x %d cols (%d record(s) excluded)\n",
              nrow(x$data$data), ncol(x$data$data), x$n_excluded))
  cat(sprintf("  audit log: %d change record(s)\n", nrow(x$audit)))
  if (nrow(x$audit) > 0L) {
    print(table(x$audit$action))
  }
  invisible(x)
}
