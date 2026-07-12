#' A cleaning configuration
#'
#' Bundles a rule set, an action map, a record-id column, and the item
#' columns into a single object that [dcc_run()] consumes. Build one
#' programmatically with `dcc_config()`; survey staff can instead read a
#' spreadsheet with `dcc_read_config()` (planned).
#'
#' @param rules A `dcc_ruleset` from [dcc_rules()].
#' @param actions Named list mapping `check_id`s to actions (see
#'   [dcc_execute()]).
#' @param id_var Record-id column name, or `NULL` for row numbers.
#' @param items Optional character vector of item column names.
#' @return A `dcc_config` object.
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    variable: score", "    min: 0", "    max: 100"), rf)
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"),
#'              id_var = "sid")
#' }
#' @export
dcc_config <- function(rules, actions = list(), id_var = NULL, items = NULL) {
  if (!inherits(rules, "dcc_ruleset")) {
    dcc_abort("`rules` must be a dcc_ruleset from dcc_rules().",
              class = "dcc_type_error")
  }
  if (!is.list(actions) ||
      (length(actions) &&
       (is.null(names(actions)) || any(!nzchar(names(actions)))))) {
    dcc_abort("`actions` must be a named list mapping check_id to actions.",
              class = "dcc_config_error")
  }
  structure(list(rules = rules, actions = actions,
                 id_var = id_var, items = items),
            class = "dcc_config")
}

#' @export
print.dcc_config <- function(x, ...) {
  cat(sprintf("<dcc_config> %d check(s), %d action(s), id_var = %s\n",
              length(x$rules$checks), length(x$actions),
              x$id_var %||% "<row number>"))
  invisible(x)
}

#' Validate a cleaning configuration
#'
#' Runs [dcc_validate_rules()] over the config's rules and additionally
#' checks that every action targets a `check_id` the rules can produce.
#'
#' @param config A `dcc_config` from [dcc_config()].
#' @return A `dcc_validation` object.
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    variable: score", "    min: 0", "    max: 100"), rf)
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   cfg <- dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"))
#'   dcc_validate_config(cfg)
#' }
#' @export
dcc_validate_config <- function(config) {
  if (!inherits(config, "dcc_config")) {
    dcc_abort("`config` must be a dcc_config from dcc_config().",
              class = "dcc_type_error")
  }
  vr <- dcc_validate_rules(config$rules)
  produced <- produced_check_ids(config$rules)
  unknown <- setdiff(names(config$actions), produced)
  extra <- if (length(unknown)) {
    list(val_issue("CONFIG_UNKNOWN_ACTION", "fail",
                   paste(unknown, collapse = ", "),
                   fix = "Every action must target a check the rules produce."))
  } else {
    list()
  }
  combined <- data.table::rbindlist(c(list(vr), extra))
  data.table::setattr(combined, "class",
                      c("dcc_validation", class(data.table::data.table())))
  combined[]
}

# The check_ids a rule set produces: the declared id for range/set/expr,
# the detector-native id for detector rules.
produced_check_ids <- function(rules) {
  detector_ids <- list(
    missing_items = "Q_MISSING_ITEMS",
    straightlining = "Q_STRAIGHTLINING",
    response_time = "Q_RESPONSE_TIME",
    trap_items = "Q_TRAP_ITEMS",
    score_anomaly = c("Q_SCORE_OUTLIER", "Q_GROUP_SCORE_SHIFT")
  )
  ids <- character()
  for (ch in rules$checks) {
    type <- ch$type %||% ""
    if (type %in% c("range", "set", "expr")) {
      ids <- c(ids, as.character(ch$id))
    } else if (type %in% names(detector_ids)) {
      ids <- c(ids, detector_ids[[type]])
    }
  }
  unique(ids)
}

#' Run a cleaning workflow with one command
#'
#' The survey-staff entry point: orchestrates the Detect -> Execute ->
#' Report pipeline from a [dcc_config()] and writes a fixed output
#' layout. Preview is the default, so the safe path requires no extra
#' care, and the raw input file is never modified in any mode.
#'
#' Modes:
#' * `"preview"` -- detect and report only; no data change, and no
#'   `cleaned-data.csv` is written.
#' * `"execute"` -- apply the configured actions and write the cleaned
#'   data, audit log, and manifest.
#' * `"verify"` -- like `execute`, plus a reconciliation summary.
#' * `"rerun"` -- reproduce a previous run from its `manifest.yaml`
#'   (pass the manifest path as `data`, or keep it in `output_dir`).
#'
#' Output layout (written under `output_dir`): `cleaned-data.csv`
#' (execute/verify), `findings.xlsx` (or `findings.csv` without the
#' `writexl` package), `audit-log.csv` (execute/verify),
#' `management-report.html`, `audit-report.html`, `manifest.yaml`
#' (execute/verify), and `run-summary.txt`.
#'
#' @param data A data file path, a `dcc_data`, or a data.frame (or a
#'   manifest path in `"rerun"` mode).
#' @param config A `dcc_config` from [dcc_config()] /
#'   `dcc_read_config()`.
#' @param output_dir Directory for the fixed output layout (created if
#'   needed).
#' @param mode One of `"preview"` (default), `"execute"`, `"verify"`,
#'   `"rerun"`.
#' @param id_var Record-id column; defaults to the config's `id_var`.
#' @return A `dcc_run` object with the mode, config, and written file
#'   paths (via [dcc_run_files()]).
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    variable: score", "    min: 0", "    max: 100"), rf)
#' csv <- tempfile(fileext = ".csv")
#' writeLines(c("sid,score", "S1,90", "S2,150"), csv)
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   cfg <- dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"),
#'                     id_var = "sid")
#'   run <- dcc_run(csv, cfg, tempfile("dcc-out"), mode = "preview")
#'   dcc_run_files(run)
#' }
#' @export
dcc_run <- function(data, config, output_dir,
                    mode = c("preview", "execute", "verify", "rerun"),
                    id_var = NULL) {
  mode <- match.arg(mode)
  if (!inherits(config, "dcc_config")) {
    dcc_abort("`config` must be a dcc_config from dcc_config() or ",
              "dcc_read_config().", class = "dcc_type_error")
  }
  id_var <- id_var %||% config$id_var
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  wpath <- function(name) file.path(output_dir, name)
  written <- character()
  mark <- function(p) written <<- c(written, p)

  if (mode == "rerun") {
    manifest <- if (is.character(data) && length(data) == 1L &&
                    grepl("\\.ya?ml$", data, ignore.case = TRUE)) {
      data
    } else {
      wpath("manifest.yaml")
    }
    rr <- dcc_rerun(manifest)
    summ <- wpath("run-summary.txt")
    writeLines(c("DCC run summary", "mode: rerun",
                 paste0("reproduced: ", rr$reproduced),
                 paste0("data_match: ", rr$data_match),
                 paste0("audit_match: ", rr$audit_match)), summ)
    mark(summ)
    return(new_dcc_run(mode, config, id_var, written, rr))
  }

  x <- if (inherits(data, "dcc_data")) {
    data
  } else if (is.character(data) && length(data) == 1L) {
    dcc_read(data)
  } else {
    dcc_data(data.table::as.data.table(data))
  }

  errs <- dcc_validation_errors(dcc_doctor(x, config$rules, id_var))
  if (nrow(errs)) {
    dcc_abort("Validation failed (", nrow(errs), " blocking issue(s); first: ",
              errs$code[1L], "). Inspect with dcc_doctor().",
              class = "dcc_run_error")
  }

  found <- dcc_detect(x, config$rules, id_var = id_var)
  actions <- if (mode == "preview") list() else config$actions
  res <- dcc_execute(x, found, actions = actions, id_var = id_var)

  fnd <- as.data.frame(res$findings)
  if (requireNamespace("writexl", quietly = TRUE)) {
    p <- wpath("findings.xlsx")
    writexl::write_xlsx(fnd, p)
  } else {
    p <- wpath("findings.csv")
    data.table::fwrite(fnd, p)
  }
  mark(p)

  mp <- wpath("management-report.html")
  dcc_report(res, mp, audience = "summary")
  mark(mp)
  ap <- wpath("audit-report.html")
  dcc_report(res, ap, audience = "audit")
  mark(ap)

  rec <- dcc_reconcile(res)

  if (mode %in% c("execute", "verify")) {
    cp <- wpath("cleaned-data.csv")
    data.table::fwrite(as.data.frame(dcc_cleaned(res)$data), cp)
    mark(cp)
    al <- wpath("audit-log.csv")
    dcc_export_log(res, al, format = "csv")
    mark(al)
    mf <- wpath("manifest.yaml")
    ok <- tryCatch({
      dcc_manifest(res, path = mf)
      TRUE
    }, dcc_manifest_error = function(e) FALSE)
    if (ok) mark(mf)
  }

  summ <- wpath("run-summary.txt")
  writeLines(c(
    "DCC run summary",
    paste0("mode: ", mode),
    paste0("findings: ", nrow(res$findings)),
    paste0("changes: ", nrow(dcc_audit_log(res))),
    paste0("excluded: ", res$n_excluded),
    paste0("unhandled: ", nrow(res$unhandled)),
    paste0("handled: ", sum(rec$handled), "/", nrow(rec))
  ), summ)
  mark(summ)

  new_dcc_run(mode, config, id_var, written, res)
}

new_dcc_run <- function(mode, config, id_var, files, result) {
  structure(list(mode = mode, config = config, id_var = id_var,
                 files = files, result = result),
            class = "dcc_run")
}

#' Output files written by a run
#'
#' @param x A `dcc_run` from [dcc_run()].
#' @return A character vector of the file paths the run wrote.
#' @examples
#' rf <- tempfile(fileext = ".yaml")
#' writeLines(c("checks:", "  - id: R001", "    type: range",
#'              "    variable: score", "    min: 0", "    max: 100"), rf)
#' csv <- tempfile(fileext = ".csv")
#' writeLines(c("sid,score", "S1,90", "S2,150"), csv)
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   cfg <- dcc_config(dcc_rules(rf), id_var = "sid")
#'   dcc_run_files(dcc_run(csv, cfg, tempfile("dcc-out")))
#' }
#' @export
dcc_run_files <- function(x) {
  if (!inherits(x, "dcc_run")) {
    dcc_abort("`x` must be a dcc_run from dcc_run().", class = "dcc_type_error")
  }
  x$files
}

#' @export
print.dcc_run <- function(x, ...) {
  cat(sprintf("<dcc_run> mode = %s, %d file(s)\n", x$mode, length(x$files)))
  for (f in x$files) cat("  ", f, "\n", sep = "")
  invisible(x)
}
