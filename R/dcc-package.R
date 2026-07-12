#' DCC: Data Cleaning Center for Survey and Assessment Data
#'
#' Rule-driven, auditable cleaning of survey and assessment response data,
#' implementing the WeianData Detect-Execute-Report workflow. See
#' `docs/design.md` in the repository for the full design document.
#'
#' @section Scope (through v0.5):
#' * [dcc_read()] / [dcc_data()] / [dcc_l0_diagnose()] -- multi-format,
#'   multi-encoding input layer, container with provenance, level-0
#'   diagnostics.
#' * [dcc_rules()] / [dcc_detect()] and the `detect_*` family -- the
#'   declarative YAML rule engine and five response-quality detectors.
#' * [dcc_execute()] / [dcc_score()] / [dcc_map_forms()] -- execution
#'   with a cell-level audit log, answer-key scoring, form mapping.
#' * [dcc_report()] / [dcc_trace()] / [dcc_rerun()] -- dual-layer
#'   reports, cell lineage, manifest-based reproduction.
#' * [dcc_detect_chunked()] -- larger-than-memory detection with an
#'   adaptive CSV/Arrow backend.
#'
#' @keywords internal
#' @import data.table
#' @importFrom stringi stri_enc_detect stri_conv stri_read_raw
#' @importFrom tools md5sum file_ext
#' @importFrom utils packageVersion head
"_PACKAGE"

# data.table NSE variables used in this package
utils::globalVariables(c(".", ".N", ".SD", "name", "n_missing",
                         "pct_missing", ".dcc_id", ".dcc_score",
                         ".dcc_group", ".dcc_lo", ".dcc_hi", ".dcc_mu",
                         ".dcc_sd", ".dcc_gmu", "type", "points",
                         "partial", "form", "source", "master",
                         "is_anchor", "record_id", "check_id", "action",
                         "handled", "dimension", "severity"))

dcc_version_string <- function() {
  as.character(utils::packageVersion("DCC"))
}

dcc_timestamp <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
}

`%||%` <- function(x, y) if (is.null(x)) y else x

dcc_abort <- function(..., class = "dcc_error") {
  stop(errorCondition(paste0(...), class = c(class, "dcc_error")))
}

dcc_require <- function(pkg, purpose) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    dcc_abort(
      "Package '", pkg, "' is required to ", purpose, ". ",
      "Install it with install.packages(\"", pkg, "\").",
      class = "dcc_missing_dependency"
    )
  }
}
