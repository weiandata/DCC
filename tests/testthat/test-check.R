test_that("dcc_check previews without changing input or applying actions", {
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150"), data)
  plan <- write_plan_workbook(plan_fixture(data))
  before <- unname(tools::md5sum(data))
  out <- tempfile("dcc-check")

  result <- dcc_check(data, plan, out)

  expect_s3_class(result, "dcc_check_result")
  expect_identical(unname(tools::md5sum(data)), before)
  expect_identical(result$status, "ready")
  expect_identical(result$data$data$score, c(90, 150))
  expect_equal(nrow(result$findings), 1L)
  expect_true(file.exists(file.path(out, "validation.xlsx")))
  expect_true(file.exists(file.path(out, "preview-findings.xlsx")))
  expect_true(file.exists(file.path(out, "staff-report.html")))
  expect_true(file.exists(file.path(out, "run-summary.txt")))
  expect_false(file.exists(file.path(out, "cleaned-data.csv")))
  expect_false(file.exists(file.path(out, "manifest.yaml")))
})

test_that("dcc_check publishes invalid-plan diagnostics without importing", {
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90"), data)
  plan <- plan_fixture(data)
  plan$columns$type[2] <- "numbr"
  path <- write_plan_workbook(plan)
  out <- tempfile("dcc-check")

  result <- dcc_check(data, path, out)

  expect_identical(result$status, "invalid")
  expect_true("PLAN_COLUMN_TYPE" %in% result$validation$code)
  expect_true(file.exists(file.path(out, "validation.xlsx")))
  expect_true(file.exists(file.path(out, "staff-report.html")))
  expect_false(file.exists(file.path(out, "preview-findings.xlsx")))
})

test_that("dcc_check refuses existing outputs and invalid argument types", {
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90"), data)
  plan <- write_plan_workbook(plan_fixture(data))
  out <- tempfile("dcc-check")
  dir.create(out)
  expect_error(dcc_check(data, plan, out), class = "dcc_check_error")
  expect_error(dcc_check(data.frame(sid = "S1"), plan, tempfile("check")),
               class = "dcc_check_error")
})
