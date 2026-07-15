write_yaml_rules <- function(lines) {
  rf <- tempfile(fileext = ".yaml")
  writeLines(lines, rf)
  dcc_rules(rf)
}

test_that("dcc_validate_rules reports structured rule problems", {
  skip_if_not_installed("yaml")
  rules <- write_yaml_rules(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    min: 0",
    "    max: 100"          # no `variable`
  ))
  vr <- dcc_validate_rules(rules)
  expect_s3_class(vr, "dcc_validation")
  expect_identical(names(vr),
                   c("code", "severity", "field", "rows", "fix", "workbook",
                     "sheet", "row", "column", "cell"))
  expect_true("RULE_VAR_MISSING" %in% vr$code)
  expect_true(all(dcc_validation_errors(vr)$severity == "fail"))
})

test_that("dcc_validate_rules rejects an unknown type", {
  skip_if_not_installed("yaml")
  rules <- write_yaml_rules(c(
    "checks:",
    "  - id: X1",
    "    type: teleport"
  ))
  expect_true("RULE_UNKNOWN_TYPE" %in% dcc_validate_rules(rules)$code)
})

test_that("dcc_validate_data finds duplicated ids and absent variables", {
  skip_if_not_installed("yaml")
  rules <- write_yaml_rules(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: nope",   # not a column
    "    max: 100"
  ))
  df <- data.frame(sid = c("S1", "S1", "S2"), score = c(50, 150, 70))
  vd <- dcc_validate_data(df, rules, id_var = "sid")
  expect_true("DATA_DUP_ID" %in% vd$code)
  dup <- vd$rows[[which(vd$code == "DATA_DUP_ID")]]
  expect_setequal(dup, c(1L, 2L))
  expect_true("DATA_VAR_ABSENT" %in% vd$code)
})

test_that("dcc_doctor merges reports and changes nothing", {
  skip_if_not_installed("yaml")
  rules <- write_yaml_rules(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    min: 0",
    "    max: 100"
  ))
  df <- data.frame(sid = c("S1", "S2"), score = c(50, 70))
  before <- data.table::copy(df)
  rep <- dcc_doctor(df, rules, id_var = "sid")
  expect_s3_class(rep, "dcc_validation")
  expect_identical(df, before)
  # clean inputs produce no failing issues
  expect_identical(nrow(dcc_validation_errors(rep)), 0L)
  expect_output(print(rep), "no issues")
})

test_that("dcc_doctor reports registered backend health", {
  report <- dcc_doctor(formats = c("csv", "xlsx"))
  expect_s3_class(report, "dcc_validation")
  expect_identical(nrow(dcc_validation_errors(report)), 0L)

  all_formats <- dcc_doctor(formats = "all")
  expect_true("FORMAT_LIMITATION" %in% all_formats$code)
  expect_true(any(all_formats$field == "xlsb"))
  expect_error(dcc_doctor(formats = "telepathy"),
               class = "dcc_format_error")
})
