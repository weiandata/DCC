test_that("Excel and JSON plans produce the same strict contract", {
  plan <- plan_fixture()
  excel <- dcc_read_plan(write_plan_workbook(plan))
  json <- dcc_read_plan(write_plan_json(plan))

  expect_s3_class(excel, "dcc_plan")
  expect_s3_class(json, "dcc_plan")
  expect_identical(names(excel), names(json))
  expect_identical(as.data.frame(excel$columns), as.data.frame(json$columns))
  expect_equal(nrow(dcc_validation_errors(dcc_validate_plan(excel))), 0L)
  expect_equal(nrow(dcc_validation_errors(dcc_validate_plan(json))), 0L)
})

test_that("Excel plan errors identify the exact cell", {
  path <- write_plan_workbook()
  wb <- openxlsx2::wb_load(path)
  wb <- openxlsx2::wb_add_data(wb, "columns", "numbr", start_row = 3,
                               start_col = 3, col_names = FALSE)
  openxlsx2::wb_save(wb, path, overwrite = TRUE)

  err <- dcc_validation_errors(dcc_validate_plan(dcc_read_plan(path)))
  err <- err[err$code == "PLAN_COLUMN_TYPE"]
  expect_identical(err$sheet, "columns")
  expect_identical(err$cell, "C3")
  expect_match(err$fix, "numeric")
})

test_that("unknown sheets and columns are not ignored", {
  extra_sheet <- write_plan_workbook()
  wb <- openxlsx2::wb_load(extra_sheet)
  wb <- openxlsx2::wb_add_worksheet(wb, "notes")
  openxlsx2::wb_save(wb, extra_sheet, overwrite = TRUE)
  expect_error(dcc_read_plan(extra_sheet), class = "dcc_plan_error")

  extra_column <- write_plan_workbook()
  wb <- openxlsx2::wb_load(extra_column)
  wb <- openxlsx2::wb_add_data(wb, "columns", "guess_type", start_row = 1,
                               start_col = 7, col_names = FALSE)
  openxlsx2::wb_save(wb, extra_column, overwrite = TRUE)
  expect_error(dcc_read_plan(extra_column), class = "dcc_plan_error")
})

test_that("JSON validation fields use JSON Pointers", {
  plan <- plan_fixture()
  plan$columns$type[1] <- "numbr"
  validation <- dcc_validate_plan(dcc_read_plan(write_plan_json(plan)))
  issue <- validation[validation$code == "PLAN_COLUMN_TYPE"]
  expect_identical(issue$field, "/columns/0/type")
  expect_identical(issue$cell, "")
})

test_that("dcc_read_plan rejects unsupported and missing inputs", {
  expect_error(dcc_read_plan(tempfile(fileext = ".xlsx")),
               class = "dcc_plan_error")
  path <- tempfile(fileext = ".yaml")
  writeLines("project: {}", path)
  expect_error(dcc_read_plan(path), class = "dcc_plan_error")
})
