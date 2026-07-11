test_that("dcc_findings builds and validates", {
  f <- dcc_findings(
    record_id = c("S1", "S2"),
    check_id = "CHK",
    evidence = c("a", "b"),
    severity = "warn",
    dimension = "validity"
  )
  expect_s3_class(f, "dcc_findings")
  expect_identical(nrow(f), 2L)
  expect_identical(names(f),
                   c("record_id", "variable", "check_id", "evidence",
                     "severity", "dimension"))
  expect_error(dcc_findings("S1", check_id = "C", evidence = "e",
                            severity = "catastrophic"),
               class = "dcc_type_error")
})

test_that("empty findings and binding work", {
  e <- dcc_findings()
  expect_identical(nrow(e), 0L)
  expect_s3_class(e, "dcc_findings")

  f <- dcc_findings("S1", check_id = "C", evidence = "e")
  b <- bind_findings(list(e, f, NULL))
  expect_identical(nrow(b), 1L)
  expect_s3_class(b, "dcc_findings")
})

test_that("print method runs", {
  f <- dcc_findings("S1", check_id = "C", evidence = "e")
  expect_output(print(f), "1 finding")
  expect_output(print(dcc_findings()), "0 finding")
})
