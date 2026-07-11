test_that("dcc_data validates input and builds provenance", {
  x <- dcc_data(fixture_df())
  expect_s3_class(x, "dcc_data")
  expect_s3_class(x$data, "data.table")
  expect_identical(dcc_provenance(x)$stage, "create")

  expect_error(dcc_data(1:10), class = "dcc_type_error")
})

test_that("provenance chain is append-only", {
  x <- dcc_data(fixture_df())
  x2 <- append_provenance(x, "detect", list(n_findings = 0L))
  expect_identical(vapply(x2$provenance, `[[`, "", "stage"),
                   c("create", "detect"))
  # original object untouched (copy semantics at the container level)
  expect_identical(length(x$provenance), 1L)
})

test_that("print methods run without error", {
  x <- dcc_data(fixture_df())
  expect_output(print(x), "<dcc_data>")
  expect_output(print(x), "provenance: create")

  rep <- dcc_l0_diagnose(fixture_df())
  expect_output(print(rep), "<dcc_read_report>")
})

test_that("as.data.frame and dim behave", {
  x <- dcc_data(fixture_df())
  expect_identical(dim(x), c(3L, 5L))
  expect_s3_class(as.data.frame(x), "data.frame")
})
