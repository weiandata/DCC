test_that("dcc_template writes the exact strict workbook", {
  path <- tempfile(fileext = ".xlsx")
  dcc_template(path)
  wb <- openxlsx2::wb_load(path)
  expect_identical(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("project", "source", "columns", "values", "missing", "multiselect",
      "rules", "actions", "outputs")
  )

  for (sheet in names(plan_sheet_contracts())) {
    header <- openxlsx2::wb_to_df(path, sheet = sheet, rows = 1,
                                  col_names = FALSE,
                                  skip_empty_cols = FALSE)
    expect_identical(as.character(header[1, ]),
                     plan_sheet_contracts()[[sheet]], info = sheet)
  }
})

test_that("strict workbook sheets are protected without a password", {
  path <- tempfile(fileext = ".xlsx")
  dcc_template(path)
  extracted <- tempfile("dcc-template")
  dir.create(extracted)
  utils::unzip(path, exdir = extracted)
  sheets <- Sys.glob(file.path(extracted, "xl", "worksheets", "sheet*.xml"))
  expect_length(sheets, 9L)
  xml <- vapply(sheets, function(sheet) {
    paste(readLines(sheet, warn = FALSE), collapse = "")
  }, character(1))
  expect_true(all(grepl("<sheetProtection", xml, fixed = TRUE)))
  expect_false(any(grepl("password=", xml, fixed = TRUE)))
})

test_that("dcc_template refuses accidental overwrite and bad languages", {
  path <- tempfile(fileext = ".xlsx")
  writeLines("keep", path)
  expect_error(dcc_template(path), class = "dcc_template_error")
  expect_identical(readLines(path), "keep")
  expect_error(dcc_template(tempfile(fileext = ".xlsx"), language = "fr"),
               class = "dcc_template_error")
})

test_that("strict template exposes fixed three-audience report controls", {
  path <- tempfile(fileext = ".xlsx")
  dcc_template(path)
  outputs <- openxlsx2::wb_to_df(path, sheet = "outputs", rows = 3:9,
                                 col_names = FALSE)

  expect_identical(
    as.character(outputs[[1L]]),
    c("report_language", "cleaned_format", "include_staff_report",
      "include_statistical_report", "include_machine_report",
      "statistical_table_format", "include_sensitive_examples")
  )
})
