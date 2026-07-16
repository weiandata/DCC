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

test_that("plan validation exposes source preflight codes before import", {
  missing <- plan_fixture()
  missing$source$path <- tempfile(fileext = ".csv")
  missing_validation <- dcc_validate_plan(missing)
  expect_true(
    "IMPORT_SOURCE_MISSING" %in%
      dcc_validation_errors(missing_validation)$code
  )

  workbook <- tempfile(fileext = ".xlsx")
  writeLines("synthetic workbook placeholder", workbook)
  ambiguous <- plan_fixture()
  ambiguous$source$path <- workbook
  ambiguous$source$format <- "xlsx"
  ambiguous$source$encoding <- ""
  ambiguous$source$sheet <- ""
  ambiguous$source$range <- "A1:B3"
  ambiguous_validation <- dcc_validate_plan(ambiguous)
  expect_true(
    "IMPORT_SHEET_REQUIRED" %in%
      dcc_validation_errors(ambiguous_validation)$code
  )
})

test_that("expression rules do not require a separate variable", {
  p <- plan_fixture()
  p$rules$type <- "expr"
  p$rules$variable <- ""
  p$rules$parameters <- '{"expr":"score > 100"}'
  validation <- dcc_validate_plan(p)
  expect_false("PLAN_RULE_VARIABLE" %in% validation$code)
})

test_that("plan schema is published and exact", {
  path <- dcc_schema("plan", as = "path")
  expect_true(file.exists(path))
  schema <- dcc_schema("plan")
  expect_identical(schema$properties$project$properties$template_version$const,
                   "1.0")
  expect_false(schema$additionalProperties)
})

test_that("serialized plans match the published closed schema", {
  json <- jsonlite::toJSON(unclass(plan_fixture()), auto_unbox = TRUE,
                           dataframe = "rows", null = "null")
  value <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  schema <- dcc_schema("plan")
  expect_setequal(names(value), schema$required)
  expect_true(all(names(value) %in% names(schema$properties)))
  expect_false(schema$additionalProperties)
  expect_setequal(names(value$project), schema$properties$project$required)
  expect_true(all(names(value$project) %in%
                    names(schema$properties$project$properties)))

  bad <- value$project
  bad$unexpected <- TRUE
  expect_false(all(names(bad) %in%
                     names(schema$properties$project$properties)))
  expect_false(schema$properties$project$additionalProperties)
})
