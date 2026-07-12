run_config <- function() {
  rf <- tempfile(fileext = ".yaml")
  writeLines(c("checks:", "  - id: R001", "    type: range",
               "    variable: score", "    min: 0", "    max: 100"), rf)
  dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"), id_var = "sid")
}

write_run_csv <- function() {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S2,150", "S3,70"), csv)
  csv
}

test_that("preview reports without changing data or writing cleaned data", {
  skip_if_not_installed("yaml")
  skip_if_not_installed("writexl")
  csv <- write_run_csv()
  before <- tools::md5sum(csv)
  out <- tempfile("dcc-out")
  run <- dcc_run(csv, run_config(), out, mode = "preview")

  expect_s3_class(run, "dcc_run")
  expect_identical(tools::md5sum(csv), before)   # raw input untouched
  expect_true(file.exists(file.path(out, "findings.xlsx")))
  expect_true(file.exists(file.path(out, "management-report.html")))
  expect_false(file.exists(file.path(out, "cleaned-data.csv")))
  expect_true(any(grepl("findings", dcc_run_files(run))))
})

test_that("execute writes cleaned data, audit log and manifest", {
  skip_if_not_installed("yaml")
  skip_if_not_installed("writexl")
  csv <- write_run_csv()
  before <- tools::md5sum(csv)
  out <- tempfile("dcc-out")
  run <- dcc_run(csv, run_config(), out, mode = "execute")

  expect_identical(tools::md5sum(csv), before)   # raw input untouched
  expect_true(file.exists(file.path(out, "cleaned-data.csv")))
  expect_true(file.exists(file.path(out, "audit-log.csv")))
  expect_true(file.exists(file.path(out, "manifest.yaml")))
  rec <- dcc_reconcile(run$result)
  expect_false(any(rec$status == "unhandled"))
})

test_that("dcc_run refuses input that fails validation", {
  skip_if_not_installed("yaml")
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90", "S1,150"), csv)  # duplicated id
  out <- tempfile("dcc-out")
  expect_error(dcc_run(csv, run_config(), out, mode = "execute"),
               class = "dcc_run_error")
})

test_that("dcc_validate_config flags an action with no matching check", {
  skip_if_not_installed("yaml")
  rf <- tempfile(fileext = ".yaml")
  writeLines(c("checks:", "  - id: R001", "    type: range",
               "    variable: score", "    min: 0", "    max: 100"), rf)
  cfg <- dcc_config(dcc_rules(rf), actions = list(NOPE = "flag"))
  expect_true("CONFIG_UNKNOWN_ACTION" %in% dcc_validate_config(cfg)$code)
})
