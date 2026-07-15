test_that("dcc_plan has the exact versioned sections", {
  p <- plan_fixture()
  expect_s3_class(p, "dcc_plan")
  expect_identical(
    names(p),
    c("project", "source", "columns", "values", "missing",
      "multiselect", "rules", "actions", "outputs")
  )
  expect_identical(p$project$template_version, "1.0")
  expect_equal(nrow(dcc_validation_errors(dcc_validate_plan(p))), 0L)
})

test_that("unknown plan fields fail", {
  p <- plan_fixture()
  p$source$guess_sheet <- TRUE
  validation <- dcc_validate_plan(p)
  expect_true("PLAN_UNKNOWN_FIELD" %in% validation$code)
  expect_identical(
    validation$field[validation$code == "PLAN_UNKNOWN_FIELD"],
    "source.guess_sheet"
  )
})

test_that("plan validation checks enumerations and cross-sheet references", {
  p <- plan_fixture()
  p$columns$type[2] <- "numbr"
  p$actions$rule_id <- "NO_SUCH_RULE"
  validation <- dcc_validate_plan(p)
  expect_true(all(c("PLAN_COLUMN_TYPE", "PLAN_ACTION_RULE") %in%
                  validation$code))
})

test_that("plan schema is published and exact", {
  path <- dcc_schema("plan", as = "path")
  expect_true(file.exists(path))
  schema <- dcc_schema("plan")
  expect_identical(schema$properties$project$properties$template_version$const,
                   "1.0")
  expect_false(schema$additionalProperties)
})

test_that("serialized plans satisfy the published draft-07 schema", {
  skip_if_not_installed("jsonvalidate")
  json <- jsonlite::toJSON(unclass(plan_fixture()), auto_unbox = TRUE,
                           dataframe = "rows", null = "null")
  expect_true(jsonvalidate::json_validate(
    json, dcc_schema("plan", as = "path"), engine = "ajv"
  ))
  bad <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  bad$project$unexpected <- TRUE
  expect_false(jsonvalidate::json_validate(
    jsonlite::toJSON(bad, auto_unbox = TRUE, null = "null"),
    dcc_schema("plan", as = "path"), engine = "ajv"
  ))
})
