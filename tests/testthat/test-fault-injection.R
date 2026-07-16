test_that("unreadable inputs and malformed workbooks fail with stable classes", {
  expect_error(dcc_read(tempfile(fileext = ".csv")), class = "dcc_io_error")

  malformed <- tempfile(fileext = ".xlsx")
  writeLines("not an Excel workbook", malformed)
  expect_error(dcc_read_plan(malformed), class = "dcc_plan_error")
})

test_that("staging and publication failures cannot look successful", {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,90"), csv)
  config <- dcc_config(acceptance_ruleset(), id_var = "sid")

  testthat::local_mocked_bindings(
    new_run_staging = function(...) {
      dcc_abort("injected staging exhaustion", class = "dcc_run_error")
    },
    .package = "DCC"
  )
  expect_error(
    dcc_run(csv, config, tempfile("dcc-no-space-"), mode = "preview"),
    "injected staging exhaustion", class = "dcc_run_error"
  )
})

test_that("write failures publish machine-readable failed diagnostics", {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,150"), csv)
  config <- dcc_config(
    acceptance_ruleset(),
    actions = list(RANGE_SCORE = "set_na"), id_var = "sid"
  )
  output <- tempfile("dcc-write-failure-")
  testthat::local_mocked_bindings(
    dcc_export_log = function(...) {
      dcc_abort("injected write permission error", class = "dcc_io_error")
    },
    .package = "DCC"
  )

  error <- tryCatch(
    dcc_run(csv, config, output, mode = "execute"),
    error = identity
  )
  expect_s3_class(error, "dcc_run_error")
  diagnostic <- error$diagnostic_dir
  expect_true(dir.exists(diagnostic))
  run <- jsonlite::read_json(file.path(diagnostic, "run.json"),
                             simplifyVector = TRUE)
  expect_identical(run$status, "failed")
  expect_match(run$message, "injected write permission error")
  expect_false(dir.exists(output))
})

test_that("renderer and schema corruption remain visible", {
  model <- report_model_fixture()
  output <- withr::local_tempdir()
  dcc_report_machine(model, output)
  summary <- file.path(output, "summary.json")
  corrupted <- jsonlite::read_json(summary, simplifyVector = FALSE)
  corrupted$contract_version <- "corrupted"
  jsonlite::write_json(corrupted, summary, auto_unbox = TRUE)
  expect_false(dcc_validate_json(summary, "summary"))

  csv <- tempfile(fileext = ".csv")
  writeLines(c("sid,score", "S1,150"), csv)
  plan <- plan_with_reports(
    csv, staff = TRUE, statistical = FALSE, machine = FALSE
  )
  testthat::local_mocked_bindings(
    dcc_report_staff = function(...) stop("injected renderer failure"),
    .package = "DCC"
  )
  run <- dcc_run(csv, plan = plan, output_dir = tempfile("dcc-renderer-"),
                 mode = "execute")
  expect_identical(run$status, "partial_failure")
  expect_identical(run$manifest$reports$staff$status, "failed")
})

test_that("unavailable experimental backends report actionable codes", {
  registry <- dcc_format_registry()
  registry$xlsb$semantics$backend <- "dcc_backend_that_does_not_exist"
  testthat::local_mocked_bindings(
    dcc_format_registry = function() registry,
    .package = "DCC"
  )
  report <- dcc_doctor(formats = "xlsb")
  expect_true("FORMAT_BACKEND_MISSING" %in% report$code)
  expect_true("FORMAT_LIMITATION" %in% report$code)
})
