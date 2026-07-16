test_that("legacy public function signatures remain additive", {
  expected <- list(
    dcc_read = c("path", "format", "encoding", "..."),
    dcc_run = c("data", "config", "output_dir", "mode", "id_var", "plan"),
    dcc_report = c("x", "path", "audience", "max_rows"),
    detect_missing_items = c(
      "x", "items", "max_prop", "id_var", "severity", "structural"
    ),
    dcc_execute = c(
      "x", "findings", "actions", "id_var", "default", "ruleset_hash"
    )
  )
  for (name in names(expected)) {
    expect_identical(
      names(formals(getExportedValue("DCC", name))), expected[[name]],
      info = name
    )
  }
})

test_that("legacy read, config-run, detector, and report calls still work", {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150"), csv)
  data <- dcc_read(csv)
  expect_s3_class(data, "dcc_data")

  rules <- acceptance_ruleset()
  config <- dcc_config(
    rules, actions = list(RANGE_SCORE = "set_na"), id_var = "sid"
  )
  run <- dcc_run(
    csv, config, tempfile("dcc-legacy-run-"), mode = "preview"
  )
  expect_s3_class(run, "dcc_run")
  expect_identical(run$mode, "preview")

  direct <- detect_missing_items(
    data.frame(sid = "S1", q1 = NA, q2 = NA),
    items = c("q1", "q2"), max_prop = 0.5, id_var = "sid"
  )
  expect_true(all(direct$check_id == "Q_MISSING_ITEMS"))
  expect_true(all(direct$detector_id == "Q_MISSING_ITEMS"))

  result <- report_result_fixture()
  expect_match(dcc_report(result, audience = "summary"),
               "DCC cleaning report")
})
