test_that("one run publishes selected audience reports atomically", {
  out <- tempfile("dcc-report-run-")
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150"), data)
  plan <- plan_with_reports(data, staff = TRUE, statistical = FALSE,
                            machine = TRUE)

  run <- dcc_run(data, plan = plan, output_dir = out, mode = "execute")

  expect_true(file.exists(file.path(run$run_dir, "staff",
                                    "staff-results.xlsx")))
  expect_true(file.exists(file.path(run$run_dir, "machine", "summary.json")))
  expect_false(dir.exists(file.path(run$run_dir, "statistical")))
  expect_identical(run$manifest$status, "success")
  expect_identical(run$manifest$reports$staff$status, "success")
  expect_identical(run$manifest$reports$statistical$status, "skipped")
  expect_true(file.exists(run$manifest_path))
  expect_false(any(grepl("\\.staging-", run$files)))
})

test_that("renderer failure leaves cleaning evidence and partial manifest", {
  testthat::local_mocked_bindings(
    dcc_report_staff = function(...) stop("injected renderer failure"),
    .package = "DCC"
  )
  out <- tempfile("dcc-partial-run-")
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150"), data)
  plan <- plan_with_reports(data, staff = TRUE, statistical = FALSE,
                            machine = FALSE)

  run <- dcc_run(data, plan = plan, output_dir = out, mode = "execute")

  expect_identical(run$status, "partial_failure")
  expect_identical(run$manifest$status, "partial_failure")
  expect_identical(run$manifest$reports$staff$status, "failed")
  expect_match(run$manifest$reports$staff$error, "injected renderer failure")
  expect_true(file.exists(file.path(run$run_dir, "cleaned-data.csv")))
  expect_true(file.exists(file.path(run$run_dir, "audit-log.csv")))
  expect_true(file.exists(run$manifest_path))
  expect_false(dir.exists(out))
  expect_match(basename(run$run_dir), "\\.partial-")
})

test_that("all audience totals reconcile to the same model", {
  out <- tempfile("dcc-all-reports-")
  data <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150"), data)
  run <- dcc_run(
    data, plan = plan_with_reports(data), output_dir = out, mode = "execute"
  )

  staff <- openxlsx2::wb_to_df(
    file.path(run$run_dir, "staff", "staff-results.xlsx"),
    sheet = "运行概览"
  )
  staff_total <- staff$value[staff$key == "findings_total"]
  statistical <- data.table::fread(
    file.path(run$run_dir, "statistical", "findings.csv")
  )
  machine <- jsonlite::fromJSON(
    file.path(run$run_dir, "machine", "summary.json")
  )

  expect_equal(staff_total, nrow(statistical))
  expect_equal(staff_total, machine$counts$findings_total)
  expect_identical(machine$run_id, run$run_id)
})

test_that("legacy dcc_report API remains available", {
  html <- dcc_report(report_result_fixture(), audience = "summary")
  expect_match(html, "DCC cleaning report")
})
