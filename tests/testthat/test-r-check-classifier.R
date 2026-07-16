r_check_classifier_tool <- dcc_source_path("tools", "classify-r-check.R")

r_check_log <- function(body, status = "Status: 1 NOTE") {
  path <- tempfile(fileext = ".log")
  writeLines(c(
    "* checking CRAN incoming feasibility ... NOTE",
    body,
    "* checking package dependencies ... OK",
    "* DONE",
    status
  ), path)
  path
}

test_that("classifier allows only an exact first-submission incoming NOTE", {
  expect_true(file.exists(r_check_classifier_tool))
  source(r_check_classifier_tool, local = TRUE)
  result <- classify_r_check_log(r_check_log(c(
    "Maintainer: 'Release Owner <owner@example.com>'",
    "",
    "New submission"
  )))

  expect_identical(result$status, "pass")
  expect_identical(result$notes, 1L)
  expect_identical(result$actionable_notes, 0L)
  expect_identical(result$allowed_notes, "cran_new_submission")
})

test_that("classifier rejects extra text in the first-submission NOTE", {
  source(r_check_classifier_tool, local = TRUE)
  result <- classify_r_check_log(r_check_log(c(
    "Maintainer: 'Release Owner <owner@example.com>'",
    "",
    "New submission",
    "Version contains large components (1.2.0.9000)"
  )))

  expect_identical(result$status, "fail")
  expect_identical(result$actionable_notes, 1L)
  expect_length(result$allowed_notes, 0L)
})

test_that("classifier rejects HTML tooling and NOTE count mismatches", {
  source(r_check_classifier_tool, local = TRUE)
  html <- tempfile(fileext = ".log")
  writeLines(c(
    "* checking HTML version of manual ... NOTE",
    "Skipping checking HTML validation: tidy is outdated.",
    "* DONE",
    "Status: 1 NOTE"
  ), html)
  result <- classify_r_check_log(html)
  expect_identical(result$status, "fail")
  expect_identical(result$actionable_notes, 1L)

  mismatch <- classify_r_check_log(r_check_log(c(
    "Maintainer: 'Release Owner <owner@example.com>'", "", "New submission"
  ), status = "Status: 2 NOTEs"))
  expect_identical(mismatch$status, "fail")
  expect_identical(mismatch$actionable_notes, 1L)
})

test_that("classifier writes closed machine-readable evidence", {
  source(r_check_classifier_tool, local = TRUE)
  clean <- tempfile(fileext = ".log")
  writeLines(c("* checking tests ... OK", "* DONE", "Status: OK"), clean)
  result <- classify_r_check_log(clean)
  output <- tempfile(fileext = ".json")
  write_r_check_evidence(result, output)
  evidence <- jsonlite::read_json(output, simplifyVector = FALSE)

  expect_identical(evidence$contract_version, "1.0")
  expect_identical(evidence$status, "pass")
  expect_identical(evidence$notes, 0L)
  expect_identical(evidence$allowed_notes, list())
  expect_error(classify_r_check_log(tempfile()), "existing check log")
})
