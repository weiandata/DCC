# Format matrix: every dcc_read() backend loads its format into a
# dcc_data with the right shape and recorded format. Synthetic data
# only (repository policy: no real client data).

matrix_df <- function() {
  data.frame(
    id = c("A", "B"),
    grp = c("x", "y"),
    score = c(1.5, 2.5),
    stringsAsFactors = FALSE
  )
}

expect_read_format <- function(path, expected_format, format = "auto") {
  x <- dcc_read(path, format = format)
  expect_s3_class(x, "dcc_data")
  expect_identical(nrow(x$data), 2L)
  expect_identical(x$meta$format, expected_format)
}

test_that("dcc_read loads CSV, TSV, and tab-delimited txt", {
  df <- matrix_df()
  csv <- tempfile(fileext = ".csv")
  data.table::fwrite(df, csv)
  expect_read_format(csv, "csv")

  tsv <- tempfile(fileext = ".tsv")
  data.table::fwrite(df, tsv, sep = "\t")
  expect_read_format(tsv, "tsv")

  # a tab-delimited .txt read explicitly as tsv
  txt <- tempfile(fileext = ".txt")
  data.table::fwrite(df, txt, sep = "\t")
  expect_read_format(txt, "tsv", format = "tsv")
})

test_that("dcc_read loads JSON", {
  skip_if_not_installed("jsonlite")
  path <- tempfile(fileext = ".json")
  jsonlite::write_json(matrix_df(), path)
  expect_read_format(path, "json")
})

test_that("dcc_read loads Excel", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(matrix_df(), path)
  expect_read_format(path, "excel")
})

test_that("dcc_read loads SPSS and Stata", {
  skip_if_not_installed("haven")
  df <- matrix_df()
  sav <- tempfile(fileext = ".sav")
  haven::write_sav(df, sav)
  expect_read_format(sav, "spss")

  dta <- tempfile(fileext = ".dta")
  haven::write_dta(df, dta)
  expect_read_format(dta, "stata")
})

test_that("dcc_read loads a fixed SAS fixture", {
  skip_if_not_installed("haven")
  # haven ships a stable iris.sas7bdat; sas7bdat cannot be written from R,
  # so we read the packaged fixture rather than generate one.
  sas <- system.file("examples", "iris.sas7bdat", package = "haven")
  skip_if(!nzchar(sas), "haven SAS example fixture not available")
  x <- dcc_read(sas)
  expect_s3_class(x, "dcc_data")
  expect_identical(x$meta$format, "sas")
  expect_identical(nrow(x$data), 150L)
  expect_identical(ncol(x$data), 5L)
})

test_that("dcc_read loads Parquet and Feather", {
  skip_if_not_installed("arrow")
  df <- matrix_df()
  pq <- tempfile(fileext = ".parquet")
  arrow::write_parquet(df, pq)
  expect_read_format(pq, "parquet")

  ft <- tempfile(fileext = ".feather")
  arrow::write_feather(df, ft)
  expect_read_format(ft, "feather")
})
