builder_tool <- dcc_source_path("tools", "build-release-evidence.R")
release_tool <- dcc_source_path("tools", "verify-release.R")

write_builder_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null")
  path
}

builder_fixture_sources <- function(dir) {
  fmt_dir <- file.path(dir, "format-matrix")
  for (platform in c("x86_64-pc-linux-gnu", "aarch64-apple-darwin23",
                     "x86_64-w64-mingw32")) {
    write_builder_json(
      list(status = "pass", platform = platform, failures = list()),
      file.path(fmt_dir, paste0("format-", platform, ".json"))
    )
  }
  tarball <- file.path(dir, "DCC_1.2.0.tar.gz")
  writeLines("candidate tarball", tarball)
  list(
    coverage = write_builder_json(
      list(overall = 92.1, critical = stats::setNames(
        as.list(rep(96, 7L)),
        c("import", "validation", "rules", "execution", "audit", "rerun",
          "report-model"))),
      file.path(dir, "coverage.json")),
    property_fault = write_builder_json(
      list(repeated_runs = 5L, failures = 0L, warnings = 0L, skips = 0L),
      file.path(dir, "property-fault.json")),
    benchmark = write_builder_json(
      list(rows = 1e6, runs = 3L, summary = list(
        list(stage = "import", median_seconds = 0.8),
        list(stage = "execution", median_seconds = 9.1))),
      file.path(dir, "benchmark.json")),
    memory = write_builder_json(list(status = "pass"),
                                file.path(dir, "memory.json")),
    r_check = write_builder_json(
      list(notes = 1L, actionable_notes = 0L,
           allowed_notes = list("cran_new_submission")),
      file.path(dir, "r-check.json")),
    format_matrix_dir = fmt_dir,
    statistician = write_builder_json(
      list(correctness = list(list(passed = TRUE), list(passed = TRUE)),
           caveats = list("No inferential model selection.")),
      file.path(dir, "statistician.json")),
    agent = write_builder_json(
      list(task_count = 20L, success_rate = 1, maximum_attempts = 2L,
           unsafe_violations = 0L),
      file.path(dir, "agent.json")),
    staff = write_builder_json(list(status = "facilitator_required"),
                               file.path(dir, "staff.json")),
    tarball = tarball
  )
}

test_that("assembled evidence passes the release gate validator", {
  skip_without_dcc_source()
  expect_true(file.exists(builder_tool))
  source(builder_tool, local = TRUE)
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  now <- as.POSIXct("2026-07-18 00:00:00", tz = "UTC")

  sources <- builder_fixture_sources(withr::local_tempdir())
  evidence <- build_release_evidence(
    root, sources, release_capability_hash(root), now = now
  )

  expect_identical(evidence$contract_version, "1.1")
  issues <- dcc_validate_release_evidence(evidence, root, now)
  expect_equal(nrow(issues), 0L)
})

test_that("assembled evidence records the CI-verified platform sets", {
  skip_without_dcc_source()
  source(builder_tool, local = TRUE)
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  sources <- builder_fixture_sources(withr::local_tempdir())
  evidence <- build_release_evidence(
    root, sources, release_capability_hash(root),
    install_platforms = c("linux", "macos", "windows")
  )

  expect_setequal(unlist(evidence$gates$format_matrix$platforms),
                  c("linux", "macos", "windows"))
  expect_setequal(unlist(evidence$gates$dependencies$clean_install_platforms),
                  c("linux", "macos", "windows"))
  expect_identical(evidence$gates$benchmark$comparison_mode, "hosted_advisory")
  expect_identical(evidence$gates$statistician$all_correctness, TRUE)
})

test_that("the builder writes a file the CLI validator can read", {
  skip_without_dcc_source()
  source(builder_tool, local = TRUE)
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  now <- as.POSIXct("2026-07-18 00:00:00", tz = "UTC")
  sources <- builder_fixture_sources(withr::local_tempdir())
  evidence <- build_release_evidence(root, sources,
                                     release_capability_hash(root), now = now)

  out <- file.path(withr::local_tempdir(), "release-evidence.json")
  write_release_evidence(evidence, out)
  reread <- dcc_read_release_evidence(out)
  expect_equal(nrow(dcc_validate_release_evidence(reread, root, now)), 0L)
})

test_that("a benchmark artifact without an execution stage is rejected", {
  skip_without_dcc_source()
  source(builder_tool, local = TRUE)
  expect_error(
    evidence_execution_median(list(summary = list(list(stage = "import",
                                                       median_seconds = 1)))),
    "execution"
  )
})
