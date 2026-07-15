test_that("report model has stable sections and reconciled counts", {
  result <- report_result_fixture()
  model <- dcc_report_model(result, report_run_fixture(result))

  expect_s3_class(model, "dcc_report_model")
  expect_identical(
    names(model),
    c(
      "contract", "project", "run", "input", "plan", "validation",
      "findings", "dispositions", "changes", "exclusions",
      "reconciliation", "summaries", "scoring", "mapping", "provenance",
      "performance", "hashes", "outputs", "sensitivity"
    )
  )
  expect_identical(model$contract$version, "1.0")
  expect_equal(
    model$summaries$findings_total,
    sum(model$findings$count, na.rm = TRUE)
  )
  expect_equal(model$summaries$changes_total, nrow(model$changes))
  expect_equal(model$summaries$excluded_total, nrow(model$exclusions))
  expect_equal(nrow(dcc_validation_errors(dcc_validate_report_model(model))),
               0L)
})

test_that("report model rejects inconsistent totals with stable codes", {
  model <- report_model_fixture()
  model$summaries$findings_total <- model$summaries$findings_total + 1L

  validation <- dcc_validate_report_model(model)
  expect_true("REPORT_RECONCILIATION_FAILED" %in% validation$code)
})

test_that("report model is a defensive copy of the cleaning result", {
  result <- report_result_fixture()
  original <- result$findings$evidence
  model <- dcc_report_model(result, report_run_fixture(result))

  model$findings$evidence[1L] <- "changed outside result"
  model$changes$old_value[1L] <- "changed outside result"

  expect_identical(result$findings$evidence, original)
  expect_false("changed outside result" %in% result$audit$old_value)
})

test_that("report model schema is published as a closed contract", {
  schema <- dcc_schema("report-model")

  expect_identical(schema$title, "DCC normalized report model")
  expect_setequal(schema$required, names(report_model_fixture()))
  expect_false(schema$additionalProperties)
  expect_identical(schema$properties$contract$properties$version$const, "1.0")
})

test_that("report model validates identity, hashes, and timings", {
  model <- report_model_fixture()
  model$findings$finding_id[2L] <- model$findings$finding_id[1L]
  model$hashes$cleaned_data <- "not-a-hash"
  model$performance$total_seconds <- -1

  codes <- dcc_validate_report_model(model)$code
  expect_true("REPORT_FINDING_ID_INVALID" %in% codes)
  expect_true("REPORT_HASH_INVALID" %in% codes)
  expect_true("REPORT_TIMING_INVALID" %in% codes)
})
