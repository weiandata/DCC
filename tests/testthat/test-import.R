strict_import_spec <- function(path, columns = NULL, missing = NULL) {
  if (is.null(columns)) {
    columns <- data.frame(
      source_name = c("编号", "年龄", "性别"),
      name = c("sid", "age", "gender"),
      type = c("character", "integer", "character"),
      role = c("id", "demographic", "demographic"),
      stringsAsFactors = FALSE
    )
  }
  if (is.null(missing)) {
    missing <- data.frame(
      variable = "age",
      source_value = "-99",
      state = "declared_missing_code",
      stringsAsFactors = FALSE
    )
  }
  new_import_spec(
    path, "csv", options = list(encoding = "UTF-8"),
    columns = columns, missing = missing
  )
}

test_that("dcc_import applies declared names, types and missing codes", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "001,23,1", "002,-99,2"), f)
  spec <- strict_import_spec(f)
  x <- dcc_import(f, spec)

  expect_identical(x$data$sid, c("001", "002"))
  expect_identical(x$data$age, c(23L, NA_integer_))
  expect_identical(x$data$gender, c("1", "2"))
  expect_identical(dcc_missing_states(x)$state, "declared_missing_code")
  expect_identical(dcc_missing_states(x)$source_value, "-99")
  expect_identical(dcc_dictionary(x)$source_name, c("编号", "年龄", "性别"))
})

test_that("undeclared or missing source columns stop import", {
  extra <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别,extra", "001,23,1,x"), extra)
  expect_error(dcc_import(extra, strict_import_spec(extra)),
               "Undeclared source column", class = "dcc_import_error")

  absent <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄", "001,23"), absent)
  expect_error(dcc_import(absent, strict_import_spec(absent)),
               "Declared source column", class = "dcc_import_error")
})

test_that("failed conversions report source row and column", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "001,twenty,1"), f)
  expect_error(
    dcc_import(f, strict_import_spec(f)),
    "source row 2.*年龄", class = "dcc_import_error"
  )
})

test_that("strict import converts the declared canonical scalar types", {
  f <- tempfile(fileext = ".csv")
  writeLines(c(
    "id,n,d,flag,day,moment",
    "001,7,2.5,true,2026-07-15,2026-07-15T12:30:00Z"
  ), f)
  columns <- data.frame(
    source_name = c("id", "n", "d", "flag", "day", "moment"),
    name = c("id", "n", "d", "flag", "day", "moment"),
    type = c("character", "integer", "double", "logical", "date",
             "datetime"),
    role = c("id", rep("other", 5L)),
    stringsAsFactors = FALSE
  )
  spec <- strict_import_spec(f, columns = columns, missing = data.frame())
  x <- dcc_import(f, spec)
  expect_identical(x$data$id, "001")
  expect_identical(x$data$n, 7L)
  expect_identical(x$data$d, 2.5)
  expect_identical(x$data$flag, TRUE)
  expect_s3_class(x$data$day, "Date")
  expect_s3_class(x$data$moment, "POSIXct")
})

test_that("import binds the declared source and records reproducible hashes", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "001,23,1"), f)
  spec <- strict_import_spec(f)
  other <- tempfile(fileext = ".csv")
  writeLines(readLines(f), other)
  expect_error(dcc_import(other, spec), "does not match",
               class = "dcc_import_error")

  x <- dcc_import(f, spec)
  expect_identical(hash_import_spec(spec),
                   hash_import_spec(strict_import_spec(f)))
  p <- dcc_provenance(x)
  expect_identical(p$stage, "import")
  expect_true(nzchar(p$hashes[[1L]]$input))
  expect_true(nzchar(p$hashes[[1L]]$import_spec))
})

test_that("strict adapters reject options that weaken raw preservation", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "001,23,1"), f)
  spec <- strict_import_spec(f)
  spec$options$colClasses <- "integer"
  expect_error(dcc_import(f, spec), "protected option",
               class = "dcc_import_error")
})

test_that("dcc_import requires an import specification", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("sid", "S1"), f)
  expect_error(dcc_import(f, list()), class = "dcc_type_error")
})
