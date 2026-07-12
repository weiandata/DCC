#' Machine-readable DCC capability document
#'
#' Returns a versioned, deterministic description of every public
#' capability, rule type, action type, and input format, plus the
#' operations DCC deliberately does not support. General-purpose callers
#' (including AI systems) can query it to discover what is Stable,
#' Experimental, or Planned before building a pipeline, instead of
#' guessing from documentation.
#'
#' The `status` of each feature reflects the *implemented* state of the
#' installed package, not a roadmap: a capability is `"Stable"` only when
#' it is exported and tested, `"Planned"` when it is designed but not yet
#' implemented.
#'
#' @return A named list with:
#'   * `contract_version` -- the capability-contract version (a string).
#'   * `package_version` -- the installed DCC version.
#'   * `features` -- a data.frame of `name`, `status`
#'     (`"Stable"`/`"Experimental"`/`"Planned"`), and `since`.
#'   * `rule_types` -- the supported declarative rule/detector types.
#'   * `action_types` -- the supported execution action names.
#'   * `formats` -- a data.frame of `format` and its `reader`.
#'   * `unsupported` -- operations DCC does not perform.
#' @examples
#' caps <- dcc_capabilities()
#' caps$action_types
#' caps$features[caps$features$status == "Stable", "name"]
#' @export
dcc_capabilities <- function() {
  list(
    contract_version = "1.1",
    package_version = dcc_version_string(),
    features = dcc_capability_features(),
    rule_types = dcc_rule_types(),
    action_types = dcc_action_types(),
    formats = dcc_read_formats_table(),
    unsupported = c("impute", "deductive_correct", "irtc", "duckdb",
                    "pdf_output", "psychometrics")
  )
}

# --- single sources of truth, shared with the engine -----------------

# The execution actions dcc_execute() accepts. dcc_execute()'s validator
# uses this same vector, so the capability document cannot drift from the
# implementation.
dcc_action_types <- function() {
  c("exclude", "set_na", "flag", "recode")
}

# The declarative rule/detector types dcc_detect() evaluates.
dcc_rule_types <- function() {
  c("range", "set", "expr", "skip_logic", "missing_items", "straightlining",
    "response_time", "trap_items", "score_anomaly")
}

# The input formats dcc_read() understands (excluding "auto"). dcc_read()
# builds its match.arg set from this vector.
dcc_read_formats <- function() {
  c("csv", "tsv", "excel", "spss", "stata", "sas", "parquet",
    "feather", "json")
}

dcc_read_formats_table <- function() {
  data.frame(
    format = dcc_read_formats(),
    reader = c("data.table::fread", "data.table::fread",
               "readxl::read_excel", "haven::read_sav",
               "haven::read_dta", "haven::read_sas",
               "arrow::read_parquet", "arrow::read_feather",
               "jsonlite::fromJSON"),
    stringsAsFactors = FALSE
  )
}

dcc_capability_features <- function() {
  feat <- function(name, status, since) {
    list(name = name, status = status, since = since)
  }
  rows <- list(
    feat("detect_execute_report", "Stable", "0.5.0"),
    feat("rule_range_set_expr", "Stable", "0.5.0"),
    feat("detectors_five", "Stable", "0.5.0"),
    feat("scoring", "Stable", "0.5.0"),
    feat("map_forms", "Stable", "0.5.0"),
    feat("read_formats", "Stable", "1.0.1"),
    feat("chunked_detection", "Stable", "1.0.1"),
    feat("finding_id", "Stable", "1.0.1"),
    feat("reconciliation_exact", "Stable", "1.0.1"),
    feat("execute_preflight", "Stable", "1.0.1"),
    feat("capabilities", "Stable", "1.1.0"),
    feat("public_accessors", "Stable", "1.1.0"),
    feat("json_schemas", "Stable", "1.1.0"),
    feat("validators", "Stable", "1.1.0"),
    feat("one_command_run", "Stable", "1.1.0"),
    feat("apply_codebook", "Stable", "1.1.0"),
    feat("skip_logic", "Stable", "1.1.0"),
    feat("excel_config", "Stable", "1.1.0"),
    feat("to_irtc", "Planned", NA_character_)
  )
  data.frame(
    name = vapply(rows, `[[`, character(1), "name"),
    status = vapply(rows, `[[`, character(1), "status"),
    since = vapply(rows, `[[`, character(1), "since"),
    stringsAsFactors = FALSE
  )
}
