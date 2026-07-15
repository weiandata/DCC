test_that("ZIP requires a safe explicit member", {
  expect_error(resolve_compressed_source("x.zip", list()),
               "explicit.*member", class = "dcc_import_error")
  expect_error(validate_zip_member("../secret.csv"),
               class = "dcc_import_error")
  expect_error(validate_zip_member("folder\\..\\secret.csv"),
               class = "dcc_import_error")
  expect_error(validate_zip_member("/absolute.csv"),
               class = "dcc_import_error")
  expect_error(validate_zip_member("folder/"),
               class = "dcc_import_error")
})

test_that("gzip sources import without changing compressed bytes", {
  gz <- tempfile(fileext = ".csv.gz")
  con <- gzfile(gz, open = "wt", encoding = "UTF-8")
  writeLines(c("编号,年龄,性别", "001,23,1"), con)
  close(con)
  before <- tools::md5sum(gz)
  spec <- strict_import_spec(gz)
  x <- dcc_import(gz, spec)
  expect_identical(x$data$sid, "001")
  expect_identical(tools::md5sum(gz), before)
  expect_error(
    resolve_compressed_source(gz, list(max_uncompressed_bytes = 5)),
    "size limit", class = "dcc_import_error"
  )
})

test_that("ZIP extracts only the declared member for import", {
  skip_if(Sys.which("zip") == "", "zip utility is unavailable")
  work <- tempfile("dcc-zip-source")
  dir.create(work)
  csv <- file.path(work, "responses.csv")
  writeLines(c("编号,年龄,性别", "001,23,1"), csv)
  zipfile <- tempfile(fileext = ".zip")
  old <- setwd(work)
  on.exit(setwd(old), add = TRUE)
  utils::zip(zipfile, files = "responses.csv")

  spec <- strict_import_spec(zipfile)
  spec$options$member <- "responses.csv"
  x <- dcc_import(zipfile, spec)
  expect_identical(x$data$sid, "001")

  absent <- strict_import_spec(zipfile)
  absent$options$member <- "missing.csv"
  expect_error(dcc_import(zipfile, absent), "not found",
               class = "dcc_import_error")
})
