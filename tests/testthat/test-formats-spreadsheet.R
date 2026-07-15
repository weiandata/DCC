spreadsheet_fixture <- function(format) {
  expected <- data.frame(
    sid = c("001", "002"),
    date = c("2026-07-01", "2026-07-02"),
    q1 = c("1", "-99"),
    stringsAsFactors = FALSE
  )
  typed <- expected
  typed$date <- as.Date(typed$date)
  if (format == "xlsx") {
    path <- tempfile(fileext = ".xlsx")
    writexl::write_xlsx(list(responses = typed), path)
  } else if (format == "ods") {
    path <- tempfile(fileext = ".ods")
    readODS::write_ods(typed, path, sheet = "responses")
  } else {
    stop("unknown fixture format")
  }
  list(path = path, expected = expected)
}

test_that("XLSX and ODS adapters preserve declared raw values", {
  skip_if_not_installed("writexl")
  for (format in c("xlsx", "ods")) {
    fixture <- spreadsheet_fixture(format)
    got <- dcc_get_adapter(format)$reader(
      fixture$path,
      list(sheet = "responses", range = "A1:C3")
    )$data
    expect_identical(as.data.frame(got), fixture$expected, info = format)
  }
})

test_that("legacy XLS uses the same character-preserving contract", {
  path <- system.file("extdata", "clippy.xls", package = "readxl")
  raw <- dcc_get_adapter("xls")$reader(
    path, list(sheet = "list-column", range = "A1:B5")
  )$data
  expect_identical(names(raw), c("name", "value"))
  expect_identical(raw$name[1L], "Name")
  expect_true(is.character(raw$value))
})

test_that("spreadsheet structure must declare sheet and range", {
  skip_if_not_installed("writexl")
  fixture <- spreadsheet_fixture("xlsx")
  expect_error(
    dcc_get_adapter("xlsx")$reader(fixture$path, list(sheet = "responses")),
    "range", class = "dcc_import_error"
  )
  expect_error(
    dcc_get_adapter("xlsx")$reader(fixture$path, list(range = "A1:C3")),
    "sheet", class = "dcc_import_error"
  )
})

test_that("spreadsheet adapters feed strict canonical import", {
  skip_if_not_installed("writexl")
  fixture <- spreadsheet_fixture("xlsx")
  columns <- data.frame(
    source_name = c("sid", "date", "q1"),
    name = c("sid", "date", "q1"),
    type = c("character", "date", "integer"),
    role = c("id", "other", "item"),
    stringsAsFactors = FALSE
  )
  missing <- data.frame(variable = "q1", source_value = "-99",
                        state = "declared_missing_code")
  spec <- new_import_spec(
    fixture$path, "xlsx",
    options = list(sheet = "responses", range = "A1:C3"),
    columns = columns, missing = missing
  )
  x <- dcc_import(fixture$path, spec)
  expect_identical(x$data$sid, c("001", "002"))
  expect_s3_class(x$data$date, "Date")
  expect_identical(x$data$q1, c(1L, NA_integer_))
})

test_that("XLSB remains Experimental with explicit limitations", {
  adapter <- dcc_get_adapter("xlsb")
  expect_identical(adapter$status, "Experimental")
  expect_true(length(adapter$semantics$limitations) >= 4L)
  invalid <- tempfile(fileext = ".xlsb")
  writeLines("not an xlsb workbook", invalid)
  expect_error(
    adapter$reader(invalid, list(sheet = "responses", range = "A1:C3")),
    "limited XLSB", class = "dcc_import_error"
  )
})
