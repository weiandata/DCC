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
  expect_true(dcc_rerun(file.path(out, "manifest.yaml"))$reproduced)
  rec <- dcc_reconcile(run$result)
  expect_false(any(rec$status == "unhandled"))
})

test_that("data-frame execution cannot silently omit a manifest", {
  skip_if_not_installed("yaml")
  out <- tempfile("dcc-out")
  expect_error(
    dcc_run(data.frame(sid = "S1", score = 150), run_config(), out,
            mode = "execute"),
    class = "dcc_run_error"
  )
  expect_false(dir.exists(out))
  failed <- Sys.glob(paste0(out, ".failed-*"))
  expect_length(failed, 1L)
  expect_true(file.exists(file.path(failed, "run.json")))
  expect_true(file.exists(file.path(failed, "run-summary.txt")))
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    diagnostic <- jsonlite::fromJSON(file.path(failed, "run.json"))
    expect_identical(diagnostic$status, "failed")
    expect_identical(diagnostic$mode, "execute")
    expect_true(nzchar(diagnostic$message))
  }
})

test_that("run IDs are unique for rapid calls in one process", {
  ids <- vapply(seq_len(100L), function(i) new_run_id(), character(1))
  expect_length(unique(ids), length(ids))
})

test_that("dcc_run refuses to overwrite an existing output directory", {
  skip_if_not_installed("yaml")
  out <- tempfile("dcc-out")
  dir.create(out)
  sentinel <- file.path(out, "keep.txt")
  writeLines("keep", sentinel)
  expect_error(dcc_run(write_run_csv(), run_config(), out),
               class = "dcc_run_error")
  expect_identical(readLines(sentinel), "keep")
  expect_length(Sys.glob(paste0(out, ".staging-*")), 0L)
})

test_that("rerun takes an explicit manifest and writes a new run directory", {
  skip_if_not_installed("yaml")
  skip_if_not_installed("writexl")
  source_out <- tempfile("dcc-source")
  dcc_run(write_run_csv(), run_config(), source_out, mode = "execute")

  rerun_out <- tempfile("dcc-rerun")
  rerun <- dcc_run(file.path(source_out, "manifest.yaml"), run_config(),
                   rerun_out, mode = "rerun")
  expect_true(rerun$result$reproduced)
  expect_true(file.exists(file.path(rerun_out, "run-summary.txt")))

  bad_out <- tempfile("dcc-rerun-bad")
  expect_error(
    dcc_run(write_run_csv(), run_config(), bad_out, mode = "rerun"),
    "manifest path", class = "dcc_run_error"
  )
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

test_that("config validation distinguishes legacy aliases from unknown IDs", {
  skip_if_not_installed("yaml")
  rf <- tempfile(fileext = ".yaml")
  writeLines(c("checks:", "  - id: M001", "    type: missing_items",
               "    items: [q1, q2]", "    max_prop: 0.4"), rf)
  cfg <- dcc_config(dcc_rules(rf),
                    actions = list(Q_MISSING_ITEMS = "flag"))
  validation <- dcc_validate_config(cfg)
  expect_false("CONFIG_UNKNOWN_ACTION" %in% validation$code)
  expect_true("CONFIG_LEGACY_ACTION_ID" %in% validation$code)
  expect_identical(
    validation$severity[validation$code == "CONFIG_LEGACY_ACTION_ID"],
    "warn"
  )
})

test_that("strict plan and compiled professional calls share results", {
  data <- write_run_csv()
  plan_path <- write_plan_workbook(plan_fixture(data))
  plan <- dcc_read_plan(plan_path)
  imported <- dcc_import(data, plan_import_spec(plan, data))
  config <- plan_config(plan)

  from_plan <- dcc_run(data, plan = plan_path,
                       output_dir = tempfile("dcc-plan"))
  professional <- dcc_run(imported, config, tempfile("dcc-config"))

  a <- as.data.frame(from_plan$result$findings)
  b <- as.data.frame(professional$result$findings)
  attr(a, "dcc_data") <- NULL
  attr(b, "dcc_data") <- NULL
  expect_identical(a, b)
  expect_identical(from_plan$mode, "preview")
  expect_s3_class(from_plan$plan, "dcc_plan")
  expect_false(any(grepl("cleaned-data", from_plan$files, fixed = TRUE)))
})

test_that("config and plan cannot both be supplied", {
  data <- write_run_csv()
  plan <- write_plan_workbook(plan_fixture(data))
  out <- tempfile("dcc-both")
  expect_error(
    dcc_run(data, config = run_config(), plan = plan, output_dir = out),
    class = "dcc_run_error"
  )
  expect_false(file.exists(out))
})

test_that("dcc_run requires one config source and plan mode is not rerun", {
  data <- write_run_csv()
  expect_error(dcc_run(data, output_dir = tempfile("dcc-none")),
               class = "dcc_run_error")
  plan <- write_plan_workbook(plan_fixture(data))
  expect_error(
    dcc_run(data, plan = plan, output_dir = tempfile("dcc-rerun-plan"),
            mode = "rerun"),
    class = "dcc_run_error"
  )
})
