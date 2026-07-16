coverage_ruleset <- function(checks, source = tempfile(fileext = ".yml")) {
  structure(
    list(checks = checks, source = source, hash = "coverage-rules"),
    class = "dcc_ruleset"
  )
}

test_that("validation rejects every malformed rule contract", {
  rules <- coverage_ruleset(list(
    list(id = "", type = "range"),
    list(id = "duplicate", type = "range", variable = "x"),
    list(id = "duplicate", type = "set", variable = "x"),
    list(id = "items", type = "missing_items"),
    list(id = "time", type = "response_time"),
    list(id = "traps", type = "trap_items"),
    list(id = "score", type = "score_anomaly"),
    list(id = "severity", type = "range", variable = "x", min = 0,
         severity = "fatal"),
    list(id = "unknown", type = "not-a-rule")
  ))

  report <- dcc_validate_rules(rules)
  expect_setequal(
    unique(report$code),
    c(
      "RULE_NO_ID", "RULE_VAR_MISSING", "RULE_RANGE_BOUNDS",
      "RULE_DUP_ID", "RULE_SET_VALUES", "RULE_ITEMS_MISSING",
      "RULE_TIMEVAR_MISSING", "RULE_TRAPS_MISSING",
      "RULE_SCOREVAR_MISSING", "RULE_BAD_SEVERITY", "RULE_UNKNOWN_TYPE"
    )
  )
  expect_error(dcc_validate_rules(list()), class = "dcc_type_error")
})

test_that("data and doctor validation expose actionable edge cases", {
  data <- data.frame(sid = c("", NA_character_, "S3"), x = 1:3)
  report <- dcc_validate_data(data, id_var = "sid")
  expect_true("DATA_NA_ID" %in% report$code)
  expect_true(all(c(1L, 2L) %in% report$rows[[1L]]))

  absent <- dcc_validate_data(data, id_var = "missing")
  expect_identical(absent$code, "DATA_NO_ID_VAR")
  expect_error(dcc_validate_data(data, rules = list()),
               class = "dcc_type_error")
  expect_equal(nrow(dcc_doctor()), 0L)
  expect_error(validate_format_backends(character()),
               class = "dcc_format_error")
  expect_error(validate_format_backends("unknown"),
               class = "dcc_format_error")
  expect_s3_class(validate_format_backends("excel"), "dcc_validation")
  expect_error(dcc_validation_errors(data.frame()),
               class = "dcc_type_error")
})

test_that("validation printing includes empty, row, and workbook locations", {
  expect_output(print(empty_validation()), "no issues")
  rows <- val_issue("ROWS", "fail", "sid", rows = 1:7, fix = "repair")
  cell <- val_issue(
    "CELL", "warn", "value", fix = "edit", sheet = "source", cell = "B4"
  )
  report <- new_validation(list(rows, cell))
  expect_output(print(report), "rows 1,2,3,4,5\\.\\.\\.")
  expect_output(print(report), "source!B4")
})

test_that("format backend validation reports outdated installed backends", {
  registry <- list(csv = adapter_delimited("csv", "csv", ","))
  registry$csv$semantics$backend <- "data.table"
  registry$csv$semantics$minimum_version <- "999.0.0"
  testthat::local_mocked_bindings(
    dcc_format_registry = function() registry,
    .package = "DCC"
  )
  report <- validate_format_backends("csv")
  expect_true("FORMAT_BACKEND_OLD" %in% report$code)
})

test_that("rule execution rejects invalid structural and declared checks", {
  data <- data.frame(sid = "S1", x = 1)
  expect_error(dcc_detect(data, list()), class = "dcc_type_error")

  missing_when <- list(
    id = "SKIP1", type = "skip_logic",
    when = list(variable = "absent", equals = 1),
    then_not_required = "x"
  )
  expect_error(
    build_structural_map(data, list(missing_when), "sid"),
    class = "dcc_rule_error"
  )
  missing_equals <- missing_when
  missing_equals$when <- list(variable = "x")
  expect_error(
    build_structural_map(data, list(missing_equals), "sid"),
    class = "dcc_rule_error"
  )
  structural <- matrix(FALSE, nrow = 1L, ncol = 1L,
                       dimnames = list(NULL, "x"))
  expect_null(subset_structural(structural, "other"))

  expect_error(
    eval_check(data, list(id = "BAD", type = "unknown"), "sid"),
    class = "dcc_rule_error"
  )
  expect_error(
    eval_range_check(data, list(id = "R", variable = "absent"), "sid",
                     "warn", NA_character_),
    class = "dcc_rule_error"
  )
  expect_error(
    eval_set_check(data, list(id = "S", variable = "absent"), "sid",
                   "warn", NA_character_),
    class = "dcc_rule_error"
  )
})

test_that("expression rules reject missing, malformed, failed, and nonlogical expressions", {
  data <- data.frame(sid = "S1", x = 1)
  evaluate <- function(expr) {
    check <- list(id = "E", type = "expr")
    if (!missing(expr)) check$expr <- expr
    eval_expr_check(data, check, "sid", "warn", NA_character_)
  }
  expect_error(evaluate(), class = "dcc_rule_error")
  expect_error(evaluate("x +"), class = "dcc_rule_error")
  expect_error(evaluate("not_available(x)"), class = "dcc_rule_error")
  expect_error(evaluate("x + 1"), class = "dcc_rule_error")
})

test_that("rule files require nonempty identifiers", {
  path <- tempfile(fileext = ".yml")
  writeLines(c("checks:", "  - type: range", "    variable: x", "    min: 0"),
             path)
  expect_error(dcc_rules(path), class = "dcc_rule_error")
})

test_that("rerun rejects missing and malformed reproduction inputs", {
  result <- report_result_fixture()
  result$data$meta$source <- tempfile(fileext = ".csv")
  expect_error(dcc_manifest(result), class = "dcc_manifest_error")
  expect_error(dcc_rerun(tempfile(fileext = ".yml")), class = "dcc_io_error")
  expect_error(dcc_rerun(list()), class = "dcc_type_error")

  missing_input <- structure(
    list(input = list(source = tempfile()), ruleset = list(source = tempfile())),
    class = "dcc_manifest"
  )
  expect_error(dcc_rerun(missing_input), class = "dcc_rerun_error")

  input <- tempfile(fileext = ".csv")
  writeLines("sid,x\nS1,1", input)
  missing_rules <- structure(
    list(
      input = list(source = input, file_hash = unname(tools::md5sum(input))),
      ruleset = list(source = tempfile())
    ),
    class = "dcc_manifest"
  )
  expect_error(dcc_rerun(missing_rules), class = "dcc_rerun_error")
})

test_that("report model constructor enforces result and run ownership", {
  result <- report_result_fixture()
  expect_error(dcc_report_model(list()), class = "dcc_type_error")
  expect_error(dcc_report_model(result, list()), class = "dcc_type_error")
  other <- report_result_fixture("other evidence")
  expect_error(
    dcc_report_model(result, report_run_fixture(other)),
    class = "dcc_report_model_error"
  )

  testthat::local_mocked_bindings(
    dcc_validate_report_model = function(...) {
      new_validation(list(val_issue("BROKEN", "fail", "model")))
    },
    .package = "DCC"
  )
  expect_error(dcc_report_model(result), class = "dcc_report_model_error")
})

test_that("report model validation rejects each closed-contract violation", {
  expect_identical(dcc_validate_report_model(1)$code, "REPORT_TYPE_INVALID")

  model <- report_model_fixture()
  missing <- model
  missing$project <- NULL
  expect_true("REPORT_SECTION_MISSING" %in%
                dcc_validate_report_model(missing)$code)
  unknown <- model
  unknown$extra <- TRUE
  expect_true("REPORT_SECTION_UNKNOWN" %in%
                dcc_validate_report_model(unknown)$code)

  reordered <- model[rev(names(model))]
  expect_true("REPORT_SECTION_ORDER_INVALID" %in%
                dcc_validate_report_model(reordered)$code)
  contract <- model
  contract$contract$version <- "9.9"
  expect_true("REPORT_CONTRACT_UNSUPPORTED" %in%
                dcc_validate_report_model(contract)$code)
  table <- model
  table$findings <- list()
  expect_true("REPORT_TABLE_INVALID" %in%
                dcc_validate_report_model(table)$code)
  ids <- model
  ids$findings$finding_id[2L] <- ids$findings$finding_id[1L]
  expect_true("REPORT_FINDING_ID_INVALID" %in%
                dcc_validate_report_model(ids)$code)
  counts <- model
  counts$summaries$input_rows <- -1
  expect_true("REPORT_COUNT_INVALID" %in%
                dcc_validate_report_model(counts)$code)
})

test_that("report helpers cover scoring, mapping, timing, and empty profiles", {
  result <- report_result_fixture()
  result$data$data$total_score <- c(10, NA_real_)
  scoring <- report_scoring(result)
  expect_identical(scoring$variable, "total_score")
  expect_equal(scoring$missing, 1L)

  result$data$provenance <- list(list(
    stage = "map_forms",
    hashes = list(form_map = paste(rep("a", 32L), collapse = "")),
    counts = list(masters = 2L, anchors = 3L),
    started_at = NA_character_, ended_at = NA_character_
  ))
  mapping <- report_mapping(result)
  expect_equal(mapping$masters, 2L)
  expect_equal(mapping$anchors, 3L)
  expect_equal(report_performance(result)$total_seconds, 0)

  profile <- build_report_profile(data.frame())
  expect_equal(profile$rows, 0L)
  expect_equal(nrow(profile$distributions), 0L)
})

test_that("compatibility import type mapping preserves source semantics", {
  expect_identical(compatibility_column_type("1", "Date"), "date")
  expect_identical(compatibility_column_type("1", "POSIXct"), "datetime")
  expect_identical(compatibility_column_type("1", "integer"), "integer")
  expect_identical(compatibility_column_type("1", "haven_labelled"), "double")
  expect_identical(compatibility_column_type("1", "logical"), "logical")
  expect_identical(compatibility_column_type(as.Date("2020-01-01")), "date")
  expect_identical(
    compatibility_column_type(as.POSIXct("2020-01-01", tz = "UTC")),
    "datetime"
  )
  expect_identical(compatibility_column_type(c("1", "2")), "integer")
  expect_identical(compatibility_column_type(c("1.5", "2.5")), "double")
  expect_identical(compatibility_column_type(c("TRUE", "FALSE")), "logical")
})

test_that("compatibility reader rejects invalid format declarations", {
  path <- tempfile(fileext = ".csv")
  writeLines("x\n1", path)
  expect_error(dcc_read(path, format = NA_character_), class = "dcc_format_error")
  expect_error(dcc_read(path, format = "excel"), class = "dcc_format_error")
  expect_error(dcc_detect_encoding(tempfile()), class = "dcc_io_error")
})

test_that("strict import rejects invalid adapters and canonical contracts", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "S1,20,F"), path)
  spec <- strict_import_spec(path)
  expect_error(dcc_import(tempfile(), spec), class = "dcc_import_error")
  expect_error(validate_adapter_result(list(data = 1), "bad"),
               class = "dcc_import_error")

  invalid_adapter <- list(
    validator = function(...) list(),
    reader = function(...) list(data = data.frame(), metadata = list()),
    name = "csv"
  )
  testthat::local_mocked_bindings(
    dcc_get_adapter = function(...) invalid_adapter,
    .package = "DCC"
  )
  expect_error(dcc_import(path, spec), class = "dcc_import_error")
})

test_that("canonical import rejects ambiguous columns and type declarations", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "S1,20,F"), path)
  spec <- strict_import_spec(path)
  raw <- data.frame(编号 = "S1", 年龄 = "20", 性别 = "F",
                    check.names = FALSE)

  duplicate <- raw
  names(duplicate)[2L] <- names(duplicate)[1L]
  expect_error(canonicalize_import(duplicate, list(), spec),
               class = "dcc_import_error")

  no_type <- spec
  no_type$columns$type <- NULL
  expect_error(canonicalize_import(raw, list(), no_type),
               class = "dcc_import_error")
  invalid_type <- spec
  invalid_type$columns$type[1L] <- "complex"
  expect_error(canonicalize_import(raw, list(), invalid_type),
               class = "dcc_import_error")

  no_role <- spec
  no_role$columns$role <- NULL
  imported <- canonicalize_import(raw, list(encoding = "UTF-8"), no_role)
  expect_true(all(imported$dictionary$role == "other"))
})

test_that("source and declared missing metadata are strictly validated", {
  invalid_contract <- data.frame(row = 1L, variable = "x")
  expect_error(source_missing_for_column(invalid_contract, "x", 1L),
               class = "dcc_import_error")
  invalid_rows <- data.frame(
    row = 2L, variable = "x", state = "unknown", source_value = "-9"
  )
  expect_error(source_missing_for_column(invalid_rows, "x", 1L),
               class = "dcc_import_error")

  expect_error(
    validate_missing_plan(data.frame(variable = "x"), "x"),
    class = "dcc_import_error"
  )
  expect_error(
    validate_missing_plan(data.frame(
      variable = "other", source_value = "-9",
      state = "declared_missing_code"
    ), "x"),
    class = "dcc_import_error"
  )
  expect_error(
    validate_missing_plan(data.frame(
      variable = "x", source_value = "-9", state = "unknown"
    ), "x"),
    class = "dcc_import_error"
  )
  duplicate <- data.frame(
    variable = c("x", "x"), source_value = c("-9", "-9"),
    state = c("declared_missing_code", "declared_missing_code")
  )
  expect_error(validate_missing_plan(duplicate, "x"),
               class = "dcc_import_error")
})

test_that("adapter constructors and delimited readers reject unsafe options", {
  fn <- function(...) NULL
  semantics <- list(backend = "base")
  expect_error(new_format_adapter("", "x", fn, fn, fn, "Stable", semantics),
               class = "dcc_format_error")
  expect_error(new_format_adapter("x", c("x", "x"), fn, fn, fn, "Stable",
                                  semantics), class = "dcc_format_error")
  expect_error(new_format_adapter("x", "x", 1, fn, fn, "Stable", semantics),
               class = "dcc_format_error")
  expect_error(new_format_adapter("x", "x", fn, fn, fn, "Broken", semantics),
               class = "dcc_format_error")
  expect_error(new_format_adapter("x", "x", fn, fn, fn, "Stable", "base"),
               class = "dcc_format_error")
  expect_error(dcc_get_adapter(character()), class = "dcc_format_error")

  path <- tempfile(fileext = ".csv")
  writeLines("x\n1", path)
  adapter <- adapter_delimited("csv", "csv", ",")
  expect_error(adapter$reader(path, list(encoding = "UTF-8", sep = ";")),
               class = "dcc_import_error")
  expect_error(adapter$reader(path, list()), class = "dcc_import_error")
})

test_that("strict plan validation accumulates staff-facing contract errors", {
  plan <- plan_fixture()
  plan$project$template_version <- "2.0"
  plan$project$language <- "fr"
  plan$project$unexpected <- "remove me"
  plan$source$encoding <- ""
  plan$source$options_json <- "[]"
  plan$source$unexpected <- "remove me"

  plan$columns$source_name[2L] <- plan$columns$source_name[1L]
  plan$columns$name[2L] <- plan$columns$name[1L]
  plan$columns$type[2L] <- "complex"
  plan$columns$role[2L] <- "id"
  plan$columns$required[2L] <- "sometimes"
  plan$values <- data.frame(
    variable = "absent", value = "1", label = "bad",
    stringsAsFactors = FALSE
  )
  plan$missing <- data.frame(
    variable = "absent", source_value = "-9", state = "unknown",
    stringsAsFactors = FALSE
  )
  plan$multiselect <- data.frame(
    item = "q1", layout = "wide", source = "q1", option = "1",
    delimiter = ",", stringsAsFactors = FALSE
  )
  plan$rules <- data.frame(
    id = c("DUP", "DUP"), type = c("range", "unknown"),
    variable = c("absent", ""), parameters = c("[]", "{"),
    severity = c("fatal", "warn"), stringsAsFactors = FALSE
  )
  plan$actions <- data.frame(
    rule_id = "absent", action = "destroy", parameters = "[]",
    stringsAsFactors = FALSE
  )
  plan$outputs <- data.frame(
    key = c(
      "report_language", "report_language", "cleaned_format",
      "include_staff_report", "statistical_table_format", "unknown"
    ),
    value = c("fr", "fr", "zip", "sometimes", "xlsx", "value"),
    stringsAsFactors = FALSE
  )

  report <- dcc_validate_plan(plan)
  expect_true(all(c(
    "PLAN_UNKNOWN_FIELD", "PLAN_TEMPLATE_VERSION", "PLAN_LANGUAGE",
    "PLAN_SOURCE_ENCODING", "PLAN_SOURCE_OPTIONS",
    "PLAN_COLUMN_DUPLICATE", "PLAN_COLUMN_TYPE", "PLAN_MULTIPLE_ID",
    "PLAN_COLUMN_REQUIRED_FLAG", "PLAN_VALUES_VARIABLE",
    "PLAN_MISSING_VARIABLE", "PLAN_MISSING_STATE",
    "PLAN_MULTISELECT_LAYOUT", "PLAN_RULE_DUPLICATE", "PLAN_RULE_TYPE",
    "PLAN_RULE_SEVERITY", "PLAN_RULE_VARIABLE", "PLAN_RULE_PARAMETERS",
    "PLAN_ACTION_RULE", "PLAN_ACTION_TYPE", "PLAN_ACTION_PARAMETERS",
    "PLAN_OUTPUT_DUPLICATE", "PLAN_OUTPUT_KEY", "PLAN_OUTPUT_LANGUAGE",
    "PLAN_OUTPUT_FORMAT", "PLAN_OUTPUT_LOGICAL",
    "PLAN_OUTPUT_TABLE_FORMAT"
  ) %in% report$code))
  expect_output(print(plan), "<dcc_plan 1.0>")
  expect_error(normalize_plan_table(list(), "columns"),
               class = "dcc_plan_error")
})

test_that("plan compilation handles every declared source option", {
  formats <- names(dcc_format_registry())
  options <- stats::setNames(lapply(formats, plan_source_option_names), formats)
  expect_true(all(vapply(options, is.character, logical(1))))
  expect_identical(plan_option_value("sheet", "2"), 2L)
  expect_equal(plan_option_value("max_uncompressed_bytes", "1024"), 1024)
  expect_equal(plan_option_value("widths", "2, 3"), c(2, 3))
  expect_identical(plan_option_value("col_names", "id, score"),
                   c("id", "score"))

  plan <- plan_fixture()
  plan$source$format <- "fwf"
  plan$source$encoding <- "UTF-8"
  plan$source$widths <- "2,3"
  plan$source$col_names <- "sid,score"
  plan$source$options_json <- '{"compression":"none"}'
  compiled <- plan_import_options(plan)
  expect_equal(compiled$widths, c(2, 3))
  expect_identical(compiled$col_names, c("sid", "score"))
  expect_error(plan_import_spec(list(), plan$source$path),
               class = "dcc_type_error")
  expect_error(plan_parameters("[1,2]", "field"), class = "dcc_plan_error")
  expect_error(plan_parameters("{", "field"), class = "dcc_plan_error")

  plan$actions <- data.frame(
    rule_id = "R001", action = "recode",
    parameters = '{"map":{"150":"100"}}', stringsAsFactors = FALSE
  )
  expect_identical(plan_actions(plan)$R001$map, c(`150` = "100"))
  plan$actions$parameters <- '{"map":["100"]}'
  expect_error(plan_actions(plan), class = "dcc_plan_error")
})
