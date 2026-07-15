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
#' Findings whose `check_id` has no entry in `actions` are returned as
#' `unhandled` (a `dcc_findings` subset) and produce no audit row: an
#' unhandled finding is never silently reported as handled. Every audit
#' row carries the exact `finding_id` of the finding that produced it,
#' and the whole execution plan is validated before any data changes.
#'
#' @param x A [dcc_data()] object or data.frame.
#' @param findings A [dcc_findings()] table from the Detect stage with
#'   unique, non-empty `finding_id` values.
#' @param actions Named list mapping `check_id`s to actions (see
#'   Details). Every name must match a `check_id` in `findings`;
#'   unknown action IDs are an error.
#' @param id_var Name of the record-id column matching the findings'
#'   `record_id`, or `NULL` for row numbers. When supplied, the column
#'   must contain non-missing, unique ids.
#' @param default Deprecated and no longer applied: findings without an
#'   explicit action are returned unhandled rather than auto-dispositioned.
#'   Retained only for call compatibility.
#' @param ruleset_hash Optional rule-file hash to stamp into the audit
#'   log (taken from the findings' `dcc_data` attribute when available).
#' @return A `dcc_result` object: list with `data` (the new
#'   [dcc_data()] version), `audit` (the cell-level audit log, whose
#'   first column is `finding_id`), `unhandled` (findings with no
#'   explicit action), and `n_excluded`. Accessors: [dcc_audit_log()],
#'   [dcc_cleaned()].
#' @export
dcc_execute <- function(x, findings, actions = list(), id_var = NULL,
                        default = "flag", ruleset_hash = NULL) {
  if (!inherits(findings, "dcc_findings")) {
    dcc_abort("`findings` must be a dcc_findings table from dcc_detect() ",
              "or a detect_*() function.", class = "dcc_type_error")
  }
  if (!is.list(actions) ||
      (length(actions) &&
       (is.null(names(actions)) || any(!nzchar(names(actions)))))) {
    dcc_abort("`actions` must be a named list mapping check_id to actions.",
              class = "dcc_execute_error")
  }
  actions <- normalize_legacy_action_ids(findings, actions)
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
  dt0 <- r$dt
  ids <- r$ids
  row_of <- split(seq_len(nrow(dt0)), ids)
  row_names <- names(row_of)

  f_rid <- findings$record_id
  f_var <- findings$variable
  f_chk <- findings$check_id
  f_id <- findings$finding_id
  # Hash record ids to row-group positions once; a per-finding
  # `row_of[[character]]` lookup is a linear scan of up to n names.
  f_pos <- match(f_rid, row_names)
  explicit <- f_chk %in% names(actions)

  # Reject an invalid execution request before any data is touched, so a
  # bad plan can never leave a half-applied dataset behind.
  validate_execution_plan(dt0, findings, actions, id_var, ids, explicit,
                          f_rid, f_var, f_chk, f_id, f_pos, row_of)

  dt <- data.table::copy(dt0)
  dispositions <- new_dispositions(findings)

  # Stamp constant fields once per run: recomputing the timestamp and
  # versions per change is both wasteful and (for timestamps) excluded
  # from reproducibility comparisons anyway.
  ts <- dcc_timestamp()
  ver <- dcc_version_string()
  rh <- ruleset_hash %||% NA_character_

  # Pre-size the audit and exclusion buffers: at most one log entry and
  # one exclusion per finding, so indexed writes stay O(1) and the whole
  # loop is linear (a growing `list[[length+1]] <-` is O(n^2)).
  n_find <- nrow(findings)
  audit <- vector("list", n_find)
  ai <- 0L
  excluded_chunks <- vector("list", n_find)
  ei <- 0L
  excluded_so_far <- rep.int(FALSE, nrow(dt))
  log_change <- function(finding_id, record_id, variable, old, new, action,
                         check_id, method) {
    ai <<- ai + 1L
    audit[[ai]] <<- data.table::data.table(
      finding_id = finding_id,
      record_id = record_id,
      variable = variable %||% NA_character_,
      old_value = as.character(old),
      new_value = as.character(new),
      action = action,
      check_id = check_id,
      method = method,
      timestamp = ts,
      dcc_version = ver,
      ruleset_hash = rh,
      keyfile_hash = NA_character_
    )
  }

  # Only findings with an explicit action are executed; the rest are
  # returned unhandled (validated above, so every action here is sound).
  for (i in which(explicit)) {
    act <- actions[[f_chk[i]]]
    act_name <- if (is.list(act)) act$action %||% "" else act
    rows <- if (is.na(f_rid[i])) integer() else row_of[[f_pos[i]]]
    dispositions$action[i] <- act_name
    if (act_name %in% c("exclude", "set_na", "recode") && length(rows) &&
        any(excluded_so_far[rows])) {
      dispositions$status[i] <- "skipped"
      dispositions$message[i] <- "record was already excluded by an earlier finding"
      next
    }
    tryCatch(
      switch(act_name,
        exclude = {
          ei <- ei + 1L
          excluded_chunks[[ei]] <- rows
          excluded_so_far[rows] <- TRUE
          log_change(f_id[i], f_rid[i], NA_character_, NA, NA, "exclude",
                     f_chk[i], "record excluded from cleaned dataset")
          dispositions$status[i] <- "excluded"
          dispositions$message[i] <- "record excluded from cleaned dataset"
        },
        set_na = {
          v <- f_var[i]
          old <- dt[[v]][rows]
          data.table::set(dt, i = rows, j = v, value = NA)
          log_change(f_id[i], rep(f_rid[i], length(rows)), v, old, NA,
                     "set_na", f_chk[i], "cell set to NA")
          dispositions$status[i] <- "changed"
          dispositions$message[i] <- "cell set to NA"
        },
        recode = {
          v <- f_var[i]
          map <- act$map
          old <- dt[[v]][rows]
          key <- as.character(old)
          hitmap <- key %in% names(map)
          if (!any(hitmap)) {
            dispositions$status[i] <- "skipped"
            dispositions$message[i] <- "no recode map entry matched the current value"
          } else {
            new_vals <- old
            new_raw <- unname(map[key[hitmap]])
            new_vals[hitmap] <- methods::as(new_raw, class(dt[[v]])[1])
            data.table::set(dt, i = rows, j = v, value = new_vals)
            log_change(f_id[i], rep(f_rid[i], sum(hitmap)), v, old[hitmap],
                       new_raw, "recode", f_chk[i],
                       "cell recoded via action map")
            dispositions$status[i] <- "changed"
            dispositions$message[i] <- "cell recoded via action map"
          }
        },
        flag = {
          log_change(f_id[i], f_rid[i], f_var[i], NA, NA, "flag", f_chk[i],
                     "reviewed and kept (no data change)")
          dispositions$status[i] <- "flagged"
          dispositions$message[i] <- "reviewed and kept"
        }
      ),
      error = function(e) {
        dispositions$status[i] <- "failed"
        dispositions$message[i] <- conditionMessage(e)
        stop(errorCondition(
          paste0("Action '", act_name, "' failed for finding '", f_id[i],
                 "': ", conditionMessage(e)),
          class = c("dcc_execute_error", "dcc_error"),
          dispositions = data.table::copy(dispositions), parent = e
        ))
      }
    )
  }

  excluded_rows <- if (ei) {
    unique(unlist(excluded_chunks[seq_len(ei)], use.names = FALSE))
  } else {
    integer()
  }
  keep <- setdiff(seq_len(nrow(dt)), excluded_rows)
  cleaned_dt <- dt[keep]

  audit_dt <- if (ai) {
    data.table::rbindlist(audit[seq_len(ai)])
  } else {
    empty_audit_log()
  }

  unhandled <- findings[dispositions$status == "unhandled"]
  data.table::setattr(unhandled, "class",
                      c("dcc_findings", class(data.table::data.table())))

  base <- if (inherits(x, "dcc_data")) x else dcc_data(r$dt)
  out_data <- dcc_data(
    cleaned_dt,
    meta = base$meta,
    read_report = base$read_report,
    dictionary = base$dictionary,
    missing_states = base$missing_states,
    import_spec = base$import_spec,
    provenance = c(base$provenance, list(new_provenance_record(
      stage = "execute",
      details = list(
        n_findings = nrow(findings),
        n_changes = nrow(audit_dt),
        n_excluded = length(excluded_rows),
        n_unhandled = nrow(unhandled),
        ruleset_hash = ruleset_hash %||% NA_character_
      ),
      hashes = list(ruleset = ruleset_hash %||% NA_character_),
      counts = list(findings = nrow(findings), changes = nrow(audit_dt),
                    excluded = length(excluded_rows),
                    unhandled = nrow(unhandled))
    )))
  )

  structure(
    list(
      data = out_data,
      audit = audit_dt,
      n_excluded = length(excluded_rows),
      findings = findings,
      dispositions = dispositions,
      unhandled = unhandled,
      actions = actions,
      id_var = id_var,
      default = default,
      ruleset_hash = ruleset_hash %||% NA_character_
    ),
    class = "dcc_result"
  )
}

# Translate a detector-native action name used by an earlier DCC release to
# the declared YAML rule id. Direct detector calls keep check_id == detector_id
# and therefore do not enter this compatibility path.
normalize_legacy_action_ids <- function(findings, actions) {
  if (!length(actions) || !"detector_id" %in% names(findings)) {
    return(actions)
  }
  declared <- unique(as.character(findings$check_id))
  detector <- unique(as.character(findings$detector_id))
  legacy <- setdiff(intersect(names(actions), detector), declared)
  for (old in legacy) {
    ids <- unique(as.character(
      findings$check_id[findings$detector_id == old]
    ))
    ids <- ids[!is.na(ids) & nzchar(ids)]
    if (length(ids) != 1L || ids %in% names(actions)) {
      dcc_abort("Legacy action ID '", old,
                "' is ambiguous; use declared rule IDs.",
                class = "dcc_execute_error")
    }
    warning("Action ID '", old, "' is deprecated; use '", ids, "'.",
            call. = FALSE)
    names(actions)[names(actions) == old] <- ids
  }
  actions
}

# Validate a complete execution request before any data change. Aborts
# with `dcc_execute_error` on any integrity or action problem so the
# caller never gets a partially applied dataset.
validate_execution_plan <- function(dt, findings, actions, id_var, ids,
                                     explicit, f_rid, f_var, f_chk, f_id,
                                     f_pos, row_of) {
  if (anyNA(f_id) || any(!nzchar(f_id)) || anyDuplicated(f_id)) {
    dcc_abort("`findings` must have unique, non-empty finding_id values.",
              class = "dcc_execute_error")
  }
  if (!is.null(id_var) &&
      (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids))) {
    dcc_abort("Record ids in `id_var` '", id_var, "' must be present and ",
              "unique.", class = "dcc_execute_error")
  }
  unknown <- setdiff(names(actions), unique(f_chk))
  if (length(unknown)) {
    dcc_abort("Action(s) reference unknown check_id: ",
              paste(unknown, collapse = ", "), ".",
              class = "dcc_execute_error")
  }
  allowed <- dcc_action_types()
  for (i in which(explicit)) {
    act <- actions[[f_chk[i]]]
    act_name <- if (is.list(act)) act$action %||% "" else act
    if (!act_name %in% allowed) {
      dcc_abort("Unknown action '", act_name, "' for check '", f_chk[i],
                "'.", class = "dcc_execute_error")
    }
    group_level <- is.na(f_rid[i])
    if (group_level) {
      if (act_name != "flag") {
        dcc_abort("Group-level finding for check '", f_chk[i], "' can only ",
                  "be flagged, not '", act_name, "'.",
                  class = "dcc_execute_error")
      }
      next
    }
    if (is.na(f_pos[i])) {
      dcc_abort("Finding record_id '", f_rid[i], "' not found in data ",
                "(check `id_var`).", class = "dcc_execute_error")
    }
    if (act_name %in% c("set_na", "recode")) {
      v <- f_var[i]
      if (is.na(v) || !v %in% names(dt)) {
        dcc_abort("Finding for check '", f_chk[i], "' has no usable ",
                  "`variable`; ", act_name, " needs a cell.",
                  class = "dcc_execute_error")
      }
      if (act_name == "recode") {
        map <- act$map
        if (is.null(map) || is.null(names(map)) || any(!nzchar(names(map)))) {
          dcc_abort("recode action for check '", f_chk[i], "' needs a ",
                    "named `map`.", class = "dcc_execute_error")
        }
        old <- as.character(dt[[v]][row_of[[f_pos[i]]]])
        missing_key <- setdiff(unique(old[!is.na(old)]), names(map))
        if (length(missing_key)) {
          dcc_abort("recode map for check '", f_chk[i], "' does not cover ",
                    "observed value(s): ", paste(missing_key, collapse = ", "),
                    ".", class = "dcc_execute_error")
        }
      }
    }
  }
  invisible(TRUE)
}

empty_audit_log <- function() {
  data.table::data.table(
    finding_id = character(),
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
#' @return The cell-level audit log as a `data.table`: `finding_id`
#'   (the exact source finding), `record_id`, `variable`, `old_value`,
#'   `new_value`, `action`, `check_id`, `method`, `timestamp`,
#'   `dcc_version`, `ruleset_hash`, `keyfile_hash`.
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
