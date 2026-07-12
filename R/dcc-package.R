#' DCC: Data Cleaning Center for Survey and Assessment Data
#'
#' Rule-driven, auditable cleaning of survey and assessment response data,
#' implementing the WeianData Detect-Execute-Report workflow. See
#' `docs/design.md` in the repository for the full design document.
#'
#' @section v0.1 scope:
#' * [dcc_read()] -- multi-format, multi-encoding input layer.
#' * [dcc_data()] -- data container with provenance chain.
#' * [dcc_l0_diagnose()] -- level-0 structural diagnostics (read report).
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
