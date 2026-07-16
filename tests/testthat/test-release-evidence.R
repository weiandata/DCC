release_tool <- dcc_source_path("tools", "verify-release.R")

release_evidence_fixture <- function(root = dcc_source_root()) {
  source(release_tool, local = TRUE)
  artifact <- tempfile(fileext = ".txt")
  writeLines("release artifact", artifact)
  version <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1L]
  critical <- stats::setNames(
    as.list(rep(96, 7L)),
    c("import", "validation", "rules", "execution", "audit", "rerun",
      "report-model")
  )
  list(
    contract_version = "1.0",
    release = list(
      package = "DCC", package_version = version,
      created_at = "2026-07-16T00:00:00Z",
      expires_at = "2026-07-23T00:00:00Z",
      capability_hash = release_capability_hash(root),
      cran_version = version, internal_version = version
    ),
    gates = list(
      r_check = list(
        status = "pass", errors = 0L, warnings = 0L, notes = 0L,
        actionable_notes = 0L, allowed_notes = list(),
        test_failures = 0L, test_warnings = 0L, test_skips = 0L
      ),
      coverage = list(status = "pass", overall = 91, critical = critical),
      format_matrix = list(
        status = "pass", platforms = c("linux", "macos", "windows"),
        capability_hash = release_capability_hash(root), failures = 0L
      ),
      property_fault = list(
        status = "pass", repeated_runs = 5L, failures = 0L,
        warnings = 0L, skips = 0L
      ),
      benchmark = list(
        status = "pass", rows = 1e6, runs = 3L,
        execution_median_seconds = 8.9, maximum_regression = 0.1,
        memory_status = "pass"
      ),
      staff = list(
        status = "pass", human_evidence = TRUE, participants = 5L,
        completion_rate = 0.8, distinction_rate = 0.8, median_sus = 75,
        code_edits = 0L, raw_overwrites = 0L, signed = TRUE
      ),
      statistician = list(
        status = "pass", all_correctness = TRUE,
        caveats = c("No inferential model selection.")
      ),
      agent = list(
        status = "pass", tasks = 20L, success_rate = 0.9,
        maximum_attempts = 2L, unsafe_executions = 0L,
        validation_preview_all = TRUE, ambiguous_correct = TRUE
      ),
      dependencies = list(
        status = "pass", undeclared_calls = 0L, runtime_installers = 0L,
        complete_format_dependencies = TRUE,
        clean_install_platforms = c("linux", "macos", "windows")
      ),
      schemas = list(status = "pass", failures = 0L),
      artifacts = list(
        status = "pass", files = list(list(
          path = artifact,
          sha256 = unname(as.character(tools::sha256sum(artifact)))
        ))
      )
    )
  )
}

test_that("complete fresh release evidence passes", {
  expect_true(file.exists(release_tool))
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  evidence <- release_evidence_fixture(root)

  issues <- dcc_validate_release_evidence(
    evidence, root = root, now = as.POSIXct("2026-07-16 12:00:00", tz = "UTC")
  )
  expect_equal(nrow(issues), 0L)
  expect_invisible(dcc_assert_release_gate(evidence, root = root,
    now = as.POSIXct("2026-07-16 12:00:00", tz = "UTC")))
})

test_that("release gate rejects missing stale and capability-mismatched evidence", {
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  evidence <- release_evidence_fixture(root)
  evidence$gates$coverage <- NULL
  missing <- dcc_validate_release_evidence(evidence, root, as.POSIXct(
    "2026-07-16 12:00:00", tz = "UTC"
  ))
  expect_true("RELEASE_GATE_MISSING" %in% missing$code)

  evidence <- release_evidence_fixture(root)
  stale <- dcc_validate_release_evidence(evidence, root, as.POSIXct(
    "2026-08-01 00:00:00", tz = "UTC"
  ))
  expect_true("RELEASE_EVIDENCE_STALE" %in% stale$code)

  evidence <- release_evidence_fixture(root)
  evidence$gates$format_matrix$capability_hash <- paste(rep("0", 64), collapse = "")
  mismatch <- dcc_validate_release_evidence(evidence, root, as.POSIXct(
    "2026-07-16 12:00:00", tz = "UTC"
  ))
  expect_true("RELEASE_CAPABILITY_MISMATCH" %in% mismatch$code)
})

test_that("release gate enforces human agent coverage and artifact thresholds", {
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  now <- as.POSIXct("2026-07-16 12:00:00", tz = "UTC")
  evidence <- release_evidence_fixture(root)
  evidence$gates$staff$human_evidence <- FALSE
  evidence$gates$coverage$overall <- 89
  evidence$gates$agent$success_rate <- 0.85
  evidence$gates$artifacts$files[[1L]]$sha256 <- paste(rep("f", 64), collapse = "")
  issues <- dcc_validate_release_evidence(evidence, root, now)

  expect_true("RELEASE_STAFF_EVIDENCE_INVALID" %in% issues$code)
  expect_true("RELEASE_COVERAGE_FAILED" %in% issues$code)
  expect_true("RELEASE_AGENT_FAILED" %in% issues$code)
  expect_true("RELEASE_ARTIFACT_HASH_MISMATCH" %in% issues$code)
})

test_that("only the coded CRAN first-submission NOTE is non-actionable", {
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  now <- as.POSIXct("2026-07-16 12:00:00", tz = "UTC")
  evidence <- release_evidence_fixture(root)
  evidence$gates$r_check$notes <- 1L
  evidence$gates$r_check$allowed_notes <- list("cran_new_submission")
  expect_equal(nrow(dcc_validate_release_evidence(evidence, root, now)), 0L)

  evidence$gates$r_check$allowed_notes <- list("html_tidy_unavailable")
  unknown <- dcc_validate_release_evidence(evidence, root, now)
  expect_true("RELEASE_R_CHECK_FAILED" %in% unknown$code)

  evidence <- release_evidence_fixture(root)
  evidence$gates$r_check$notes <- 2L
  evidence$gates$r_check$allowed_notes <- list("cran_new_submission")
  mismatch <- dcc_validate_release_evidence(evidence, root, now)
  expect_true("RELEASE_R_CHECK_FAILED" %in% mismatch$code)

  evidence <- release_evidence_fixture(root)
  evidence$gates$r_check$actionable_notes <- 1L
  actionable <- dcc_validate_release_evidence(evidence, root, now)
  expect_true("RELEASE_R_CHECK_FAILED" %in% actionable$code)
})

test_that("malformed release evidence fails closed with stable issue codes", {
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  evidence <- release_evidence_fixture(root)
  evidence$release$created_at <- c("bad", "also-bad")
  evidence$gates$r_check$errors <- "not-a-number"
  evidence$gates$coverage$overall <- "not-a-number"
  evidence$gates$coverage$critical$import <- "not-a-number"
  evidence$gates$benchmark$rows <- "not-a-number"
  evidence$gates$staff$participants <- "not-a-number"
  evidence$gates$artifacts$files <- list(
    "not-an-object",
    list(path = c("one", "two"), sha256 = c("bad", "also-bad"))
  )

  issues <- expect_no_error(dcc_validate_release_evidence(
    evidence, root, as.POSIXct("2026-07-16 12:00:00", tz = "UTC")
  ))
  expect_true(all(c(
    "RELEASE_EVIDENCE_STALE", "RELEASE_R_CHECK_FAILED",
    "RELEASE_COVERAGE_FAILED", "RELEASE_BENCHMARK_FAILED",
    "RELEASE_STAFF_EVIDENCE_INVALID", "RELEASE_ARTIFACT_MISSING"
  ) %in% issues$code))
})

test_that("release evidence schema is closed and requires every gate", {
  path <- dcc_source_path("inst", "schemas", "release-evidence.schema.json")
  schema <- jsonlite::read_json(path, simplifyVector = FALSE)
  expect_false(schema$additionalProperties)
  expect_setequal(
    unlist(schema$properties$gates$required),
    c(
      "r_check", "coverage", "format_matrix", "property_fault", "benchmark",
      "staff", "statistician", "agent", "dependencies", "schemas", "artifacts"
    )
  )
  r_check <- schema$properties$gates$properties$r_check
  expect_true(all(c("actionable_notes", "allowed_notes") %in%
                    unlist(r_check$required)))
  expect_identical(
    unlist(r_check$properties$allowed_notes$items$enum),
    "cran_new_submission"
  )
})

test_that("coverage report groups every critical code area", {
  tool <- dcc_source_path("tools", "coverage-report.R")
  expect_true(file.exists(tool))
  source(tool, local = TRUE)
  detail <- data.frame(
    filename = c(
      "R/import.R", "R/validate.R", "R/rules.R", "R/execute.R",
      "R/reconcile.R", "R/rerun.R", "R/report-model.R"
    ),
    value = rep(1, 7L), stringsAsFactors = FALSE
  )
  areas <- coverage_area_summary(detail)

  expect_setequal(
    names(areas),
    c("import", "validation", "rules", "execution", "audit", "rerun",
      "report-model")
  )
  expect_true(all(unlist(areas) == 100))
})
