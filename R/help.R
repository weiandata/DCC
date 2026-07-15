dcc_workflow_help_codes <- function() {
  sort(c(
    "CHECK_DETECTION_FAILED", "CHECK_IMPORT_FAILED",
    "CONFIG_AMBIGUOUS_LEGACY_ACTION_ID", "CONFIG_LEGACY_ACTION_ID",
    "CONFIG_UNKNOWN_ACTION", "DATA_DUP_ID", "DATA_NA_ID", "DATA_NO_ID_VAR",
    "DATA_VAR_ABSENT", "FORMAT_BACKEND_MISSING", "FORMAT_BACKEND_OLD",
    "FORMAT_LIMITATION", "FORMAT_PLATFORM_UNSUPPORTED",
    "IMPORT_COLUMN_NAMES_REQUIRED", "IMPORT_DELIMITER_REQUIRED",
    "IMPORT_ENCODING_REQUIRED", "IMPORT_PROTECTED_OPTION",
    "IMPORT_RANGE_REQUIRED", "IMPORT_SHEET_REQUIRED", "IMPORT_SOURCE_MISSING",
    "IMPORT_UNKNOWN_OPTION", "IMPORT_WIDTHS_REQUIRED",
    "PLAN_ACTION_PARAMETERS", "PLAN_ACTION_RULE", "PLAN_ACTION_TYPE",
    "PLAN_COLUMN_DUPLICATE", "PLAN_COLUMN_REQUIRED",
    "PLAN_COLUMN_REQUIRED_FLAG", "PLAN_COLUMN_ROLE", "PLAN_COLUMN_TYPE",
    "PLAN_LANGUAGE", "PLAN_MISSING_FIELD", "PLAN_MISSING_SECTION",
    "PLAN_MISSING_STATE", "PLAN_MISSING_VARIABLE", "PLAN_MULTIPLE_ID",
    "PLAN_MULTISELECT_LAYOUT", "PLAN_OUTPUT_DUPLICATE", "PLAN_OUTPUT_FORMAT",
    "PLAN_OUTPUT_KEY", "PLAN_OUTPUT_LANGUAGE", "PLAN_PROJECT_REQUIRED",
    "PLAN_RULE_DUPLICATE", "PLAN_RULE_ID", "PLAN_RULE_PARAMETERS",
    "PLAN_RULE_SEVERITY", "PLAN_RULE_TYPE", "PLAN_RULE_VARIABLE",
    "PLAN_SECTION_TYPE", "PLAN_SOURCE_ENCODING", "PLAN_SOURCE_FORMAT",
    "PLAN_SOURCE_OPTIONS", "PLAN_SOURCE_REQUIRED", "PLAN_TEMPLATE_VERSION",
    "PLAN_UNKNOWN_FIELD", "PLAN_UNKNOWN_SECTION", "PLAN_VALUES_VARIABLE",
    "RULE_BAD_SEVERITY", "RULE_DUP_ID", "RULE_ITEMS_MISSING", "RULE_NO_ID",
    "RULE_RANGE_BOUNDS", "RULE_SCOREVAR_MISSING", "RULE_SET_VALUES",
    "RULE_TIMEVAR_MISSING", "RULE_TRAPS_MISSING", "RULE_UNKNOWN_TYPE",
    "RULE_VAR_MISSING"
  ))
}
read_i18n <- function(language) {
  if (!language %in% c("zh-CN", "en")) {
    dcc_abort("`language` must be `zh-CN` or `en`.", class = "dcc_help_error")
  }
  path <- system.file("i18n", paste0(language, ".csv"), package = "DCC")
  if (!nzchar(path)) {
    dcc_abort("Installed help file is missing for language: ", language,
              class = "dcc_help_error")
  }
  table <- utils::read.csv(path, stringsAsFactors = FALSE,
                           fileEncoding = "UTF-8", check.names = FALSE,
                           na.strings = character())
  required <- c("code", "explanation", "fix")
  if (!identical(names(table), required) || anyDuplicated(table$code) ||
      !setequal(table$code, dcc_workflow_help_codes())) {
    dcc_abort("Installed help file does not match the workflow code contract.",
              class = "dcc_help_error")
  }
  table
}

#' Explain a DCC workflow code in Chinese or English
#'
#' Returns stable plain-language explanations and suggested fixes for codes that
#' can appear in strict-plan validation and preflight diagnostics.
#'
#' @param code Optional stable issue code. `NULL` returns the complete table.
#' @param language `"zh-CN"` (default) or `"en"`.
#' @return A data.frame with `code`, `explanation`, and `fix`.
#' @export
dcc_help <- function(code = NULL, language = "zh-CN") {
  table <- read_i18n(language)
  if (is.null(code)) return(table)
  if (!is.character(code) || length(code) != 1L || is.na(code) ||
      !nzchar(code)) {
    dcc_abort("`code` must be one non-empty issue code.",
              class = "dcc_help_error")
  }
  hit <- table[table$code == code, , drop = FALSE]
  if (!nrow(hit)) {
    dcc_abort("Unknown help code: ", code, class = "dcc_help_error")
  }
  hit
}
