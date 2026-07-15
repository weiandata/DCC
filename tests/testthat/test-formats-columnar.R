columnar_fixture <- function(format) {
  path <- tempfile(fileext = paste0(".", format))
  data <- data.frame(sid = c("001", "002"), q1 = c(1L, -99L),
                     stringsAsFactors = FALSE)
  if (format == "parquet") {
    arrow::write_parquet(data, path)
  } else {
    arrow::write_feather(data, path)
  }
  path
}

columnar_spec <- function(path, format) {
  columns <- data.frame(
    source_name = c("sid", "q1"), name = c("sid", "q1"),
    type = c("character", "integer"), role = c("id", "item"),
    stringsAsFactors = FALSE
  )
  missing <- data.frame(variable = "q1", source_value = "-99",
                        state = "declared_missing_code")
  new_import_spec(path, format, columns = columns, missing = missing)
}

test_that("Parquet and Feather produce equal canonical tables", {
  parquet <- columnar_fixture("parquet")
  feather <- columnar_fixture("feather")
  p <- dcc_import(parquet, columnar_spec(parquet, "parquet"))
  f <- dcc_import(feather, columnar_spec(feather, "feather"))
  expect_identical(as.data.frame(p), as.data.frame(f))
  expect_identical(p$data$sid, c("001", "002"))
  expect_identical(p$data$q1, c(1L, NA_integer_))
})

test_that("columnar adapters retain Arrow schema text", {
  path <- columnar_fixture("parquet")
  raw <- dcc_get_adapter("parquet")$reader(path, list())
  expect_true(is.character(raw$metadata$schema))
  expect_true(nzchar(raw$metadata$schema))
  expect_match(raw$metadata$schema, "sid")
})
