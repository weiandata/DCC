test_that("format registry has unique names and extensions", {
  reg <- dcc_format_registry()
  expect_identical(anyDuplicated(names(reg)), 0L)
  ext <- unlist(lapply(reg, `[[`, "extensions"), use.names = FALSE)
  expect_identical(anyDuplicated(ext[ext != "txt"]), 0L)
  expect_true(all(vapply(reg, inherits, logical(1), "dcc_format_adapter")))
})

test_that("format registry contains the approved canonical formats", {
  expect_setequal(
    names(dcc_format_registry()),
    c("csv", "tsv", "txt", "fwf", "json", "jsonl", "xls", "xlsx",
      "xlsb", "ods", "spss", "stata", "sas", "xpt", "parquet",
      "feather", "rds")
  )
})

test_that("unknown formats fail with a stable error", {
  expect_error(dcc_get_adapter("telepathy"), class = "dcc_format_error")
})

test_that("adapter constructor rejects malformed contracts", {
  noop <- function(...) data.frame()
  expect_error(
    new_format_adapter("bad", "bad", NULL, noop, noop, "Planned", list()),
    class = "dcc_format_error"
  )
  expect_error(
    new_format_adapter("bad", "bad", noop, noop, noop, "Unknown", list()),
    class = "dcc_format_error"
  )
})
