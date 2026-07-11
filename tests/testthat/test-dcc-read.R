test_that("dcc_read reads a basic UTF-8 CSV", {
  f <- tempfile(fileext = ".csv")
  write_fixture_csv(f, "UTF-8")
  x <- dcc_read(f)

  expect_s3_class(x, "dcc_data")
  expect_identical(dim(x), c(3L, 5L))
  expect_identical(x$meta$format, "csv")
  expect_identical(x$meta$encoding, "UTF-8")
  expect_true(nzchar(x$meta$file_hash))

  df <- as.data.frame(x)
  expect_identical(df$student_id, c("S001", "S002", "S003"))
  expect_identical(df$q1, c(1L, 2L, NA_integer_))
  expect_identical(df$score, c(85.5, 90.0, 77.25))
})

test_that("dcc_read reads TSV via extension and explicit format", {
  f <- tempfile(fileext = ".tsv")
  write_fixture_csv(f, "UTF-8", sep = "\t")
  x <- dcc_read(f)
  expect_identical(x$meta$format, "tsv")
  expect_identical(dim(x), c(3L, 5L))

  f2 <- tempfile(fileext = ".dat")
  write_fixture_csv(f2, "UTF-8", sep = "\t")
  expect_error(dcc_read(f2), class = "dcc_format_error")
  x2 <- dcc_read(f2, format = "tsv")
  expect_identical(dim(x2), c(3L, 5L))
})

test_that("dcc_read reads rectangular JSON", {
  skip_if_not_installed("jsonlite")
  f <- tempfile(fileext = ".json")
  writeLines(
    '[{"id":"S001","q1":1},{"id":"S002","q1":2}]',
    f, useBytes = TRUE
  )
  x <- dcc_read(f)
  expect_identical(x$meta$format, "json")
  expect_identical(dim(x), c(2L, 2L))

  bad <- tempfile(fileext = ".json")
  writeLines('{"a": {"b": 1}}', bad, useBytes = TRUE)
  expect_error(dcc_read(bad), class = "dcc_format_error")
})

test_that("dcc_read errors are typed and informative", {
  expect_error(dcc_read("no-such-file.csv"), class = "dcc_io_error")
  expect_error(dcc_read(c("a.csv", "b.csv")), class = "dcc_type_error")
})

test_that("read provenance records the operation", {
  f <- tempfile(fileext = ".csv")
  write_fixture_csv(f, "UTF-8")
  x <- dcc_read(f)
  prov <- dcc_provenance(x)
  expect_identical(nrow(prov), 1L)
  expect_identical(prov$stage, "read")
  det <- prov$details[[1]]
  expect_identical(det$format, "csv")
  expect_identical(det$n_rows, 3L)
  expect_identical(det$file_hash, x$meta$file_hash)
})
