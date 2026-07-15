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
#'   * `formats` -- a data.frame of format status, extensions, backend,
#'     semantics, and limitations.
#'   * `unsupported` -- operations DCC does not perform.
#' @examples
#' caps <- dcc_capabilities()
#' caps$action_types
#' caps$features[caps$features$status == "Stable", "name"]
#' @export
dcc_capabilities <- function() {
  list(
    contract_version = "1.2",
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

# The input formats dcc_read() understands (excluding "auto"). `excel` is a
# compatibility alias resolved to xls or xlsx by extension; machine callers
# should use the registry names.
dcc_read_formats <- function() {
  c(names(dcc_format_registry()), "excel")
}

dcc_read_formats_table <- function() {
  registry <- dcc_format_registry()
  formats <- names(registry)
  out <- data.frame(
    format = formats,
    status = unname(vapply(registry, `[[`, character(1), "status")),
    backend = vapply(registry, function(adapter) {
      adapter$semantics$backend %||% NA_character_
    }, character(1)),
    stringsAsFactors = FALSE
  )
  out$extensions <- I(lapply(registry, `[[`, "extensions"))
  out$semantics <- I(lapply(registry, `[[`, "semantics"))
  out$limitations <- I(lapply(registry, function(adapter) {
    adapter$semantics$limitations %||% character()
  }))
  out
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
    feat("invalid_numeric", "Stable", "1.2.0"),
    feat("declared_yaml_ids", "Stable", "1.2.0"),
    feat("terminal_dispositions", "Stable", "1.2.0"),
    feat("atomic_run_output", "Stable", "1.2.0"),
    feat("format_adapter_registry", "Stable", "1.2.0"),
    feat("canonical_import", "Experimental", "1.2.0"),
    feat("strict_plan_contract", "Stable", "1.2.0"),
    feat("protected_excel_template", "Stable", "1.2.0"),
    feat("staff_preflight", "Stable", "1.2.0"),
    feat("bilingual_workflow_help", "Stable", "1.2.0"),
    feat("normalized_report_model", "Stable", "1.2.0"),
    feat("three_audience_reports", "Stable", "1.2.0"),
    feat("machine_report_contract", "Stable", "1.2.0"),
    feat("to_irtc", "Planned", NA_character_)
  )
  data.frame(
    name = vapply(rows, `[[`, character(1), "name"),
    status = vapply(rows, `[[`, character(1), "status"),
    since = vapply(rows, `[[`, character(1), "since"),
    stringsAsFactors = FALSE
  )
}
