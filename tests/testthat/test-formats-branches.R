# Branch coverage for the format adapters: validators, inspectors, and the
# input-validation abort paths that the happy-path import tests do not reach.
# A bare `list(options = ...)` is a sufficient stand-in for an import spec here
# because every adapter validator reads only `spec$options`.

test_that("planned_adapter is Planned and refuses every operation", {
  adapter <- planned_adapter("future", "fut")
  expect_identical(adapter$status, "Planned")
  expect_error(adapter$reader("x", list()), class = "dcc_format_error")
  expect_error(adapter$inspector("x", list()), class = "dcc_format_error")
  expect_error(adapter$validator("x", list()), class = "dcc_format_error")
})

test_that("delimited inspector and validator report structure and gaps", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("sid,age", "001,23", "002,24"), path)
  info <- dcc_get_adapter("csv")$inspector(path, list(encoding = "UTF-8"))
  expect_identical(info$columns, c("sid", "age"))
  expect_identical(info$rows, 2L)

  v <- dcc_get_adapter("csv")$validator(path, list(options = list()))
  expect_true("IMPORT_ENCODING_REQUIRED" %in% v$code)
})

test_that("columnar adapter validates source, options, and rejects bad files", {
  bad <- tempfile(fileext = ".parquet")
  writeBin(as.raw(c(1, 2, 3, 4)), bad)
  expect_error(dcc_get_adapter("parquet")$reader(bad, list()),
               class = "dcc_import_error")

  path <- tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(sid = c("001", "002"), q1 = c(1L, 2L)), path)
  info <- dcc_get_adapter("parquet")$inspector(path, list())
  expect_identical(info$columns, c("sid", "q1"))
  expect_identical(info$rows, 2L)

  miss <- dcc_get_adapter("parquet")$validator("nope.parquet",
                                               list(options = list()))
  expect_true("IMPORT_SOURCE_MISSING" %in% miss$code)
  unknown <- dcc_get_adapter("parquet")$validator(path,
                                                  list(options = list(bogus = 1)))
  expect_true("IMPORT_UNKNOWN_OPTION" %in% unknown$code)
})

test_that("statistical adapter inspects, validates, and normalizes scalars", {
  path <- tempfile(fileext = ".dta")
  haven::write_dta(data.frame(sid = c("001", "002"), age = c(1L, 2L)), path)
  info <- dcc_get_adapter("stata")$inspector(path, list())
  expect_identical(info$columns, c("sid", "age"))
  expect_identical(info$rows, 2L)

  miss <- dcc_get_adapter("stata")$validator("nope.dta", list(options = list()))
  expect_true("IMPORT_SOURCE_MISSING" %in% miss$code)
  unknown <- dcc_get_adapter("stata")$validator(path,
                                                list(options = list(bogus = 1)))
  expect_true("IMPORT_UNKNOWN_OPTION" %in% unknown$code)

  dup <- data.frame(a = 1, b = 2)
  names(dup) <- c("x", "x")
  expect_error(validate_statistical_names(dup, "spss"),
               class = "dcc_import_error")

  expect_error(statistical_scalar_character(list(1)),
               class = "dcc_import_error")
  expect_identical(
    statistical_scalar_character(as.POSIXct("2020-01-02 03:04:05", tz = "UTC")),
    "2020-01-02T03:04:05Z"
  )
  expect_identical(
    statistical_scalar_character(as.Date("2020-01-02")), "2020-01-02"
  )
})

test_that("statistical reader wraps backend failures as import errors", {
  bad <- tempfile(fileext = ".dta")
  writeBin(as.raw(rep(0, 8)), bad)
  expect_error(dcc_get_adapter("stata")$reader(bad, list()),
               class = "dcc_import_error")
})

test_that("compression resolver reports missing sources and bad limits", {
  expect_error(
    resolve_compressed_source("nope.zip", list(member = "x.csv")),
    "not found", class = "dcc_import_error"
  )
  expect_error(
    resolve_compressed_source("nope.gz", list()),
    "not found", class = "dcc_import_error"
  )
  expect_error(
    resolve_compressed_source("nope.csv", list()),
    "not found", class = "dcc_import_error"
  )
  expect_error(
    compression_size_limit(list(max_uncompressed_bytes = -1)),
    class = "dcc_import_error"
  )
  expect_identical(compression_size_limit(list()), 2 * 1024^3)
})

test_that("ZIP member over the uncompressed limit is rejected", {
  skip_if(Sys.which("zip") == "", "zip utility is unavailable")
  work <- tempfile("dcc-zip-limit")
  dir.create(work)
  csv <- file.path(work, "responses.csv")
  writeLines(c("sid,age", "001,23"), csv)
  zipfile <- tempfile(fileext = ".zip")
  old <- setwd(work)
  on.exit(setwd(old), add = TRUE)
  utils::zip(zipfile, files = "responses.csv")
  expect_error(
    resolve_compressed_source(zipfile,
                              list(member = "responses.csv",
                                   max_uncompressed_bytes = 1)),
    "size limit", class = "dcc_import_error"
  )
})

test_that("text adapter inspects and requires a single delimiter", {
  path <- tempfile(fileext = ".txt")
  writeLines(c("sid,age", "001,23"), path)
  info <- dcc_get_adapter("txt")$inspector(
    path, list(delimiter = ",", encoding = "UTF-8")
  )
  expect_identical(info$columns, c("sid", "age"))
  expect_error(
    dcc_get_adapter("txt")$reader(path, list(encoding = "UTF-8")),
    class = "dcc_import_error"
  )
  v <- dcc_get_adapter("txt")$validator(path, list(options = list()))
  expect_true("IMPORT_DELIMITER_REQUIRED" %in% v$code)
})

test_that("fixed-width adapter validates widths, names, and encoding", {
  path <- tempfile(fileext = ".txt")
  writeLines(c("00123", "00245"), path)
  opts <- list(widths = c(3L, 2L), col_names = c("sid", "age"),
               encoding = "UTF-8")
  info <- dcc_get_adapter("fwf")$inspector(path, opts)
  expect_identical(info$columns, c("sid", "age"))
  expect_identical(info$rows, 2L)

  expect_error(dcc_get_adapter("fwf")$reader(path, list(col_names = "sid")),
               class = "dcc_import_error")
  expect_error(
    dcc_get_adapter("fwf")$reader(path, list(widths = c(3L, 2L),
                                             col_names = "sid")),
    class = "dcc_import_error"
  )
  expect_error(
    dcc_get_adapter("fwf")$reader(path, list(widths = c(3L, 2L),
                                             col_names = c("sid", "age"))),
    class = "dcc_import_error"
  )

  v <- dcc_get_adapter("fwf")$validator(path, list(options = list()))
  expect_true(all(c("IMPORT_WIDTHS_REQUIRED", "IMPORT_COLUMN_NAMES_REQUIRED",
                    "IMPORT_ENCODING_REQUIRED") %in% v$code))
})

test_that("JSON adapter inspects, requires encoding, and validates", {
  path <- tempfile(fileext = ".json")
  writeLines('[{"sid":"001","age":23},{"sid":"002","age":24}]', path)
  info <- dcc_get_adapter("json")$inspector(path, list(encoding = "UTF-8"))
  expect_identical(info$columns, c("sid", "age"))
  expect_identical(info$rows, 2L)

  expect_error(dcc_get_adapter("json")$reader(path, list()),
               class = "dcc_import_error")

  miss <- dcc_get_adapter("json")$validator("nope.json", list(options = list()))
  expect_true(all(c("IMPORT_SOURCE_MISSING", "IMPORT_ENCODING_REQUIRED") %in%
                    miss$code))
})

test_that("RDS adapter inspects and reports a missing source", {
  path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(sid = c("001", "002"), age = c(1L, 2L)), path)
  info <- dcc_get_adapter("rds")$inspector(path, list())
  expect_identical(info$columns, c("sid", "age"))
  expect_identical(info$rows, 2L)

  v <- dcc_get_adapter("rds")$validator("nope.rds", list(options = list()))
  expect_true("IMPORT_SOURCE_MISSING" %in% v$code)
})
