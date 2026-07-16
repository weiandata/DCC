acceptance_path <- function(...) {
  testthat::test_path("..", "acceptance", ...)
}

test_that("staff acceptance requires signed human evidence", {
  scenarios <- yaml::read_yaml(acceptance_path("staff", "scenarios.yml"))

  expect_identical(scenarios$contract_version, "1.0")
  expect_gte(length(scenarios$scenarios), 7L)
  expect_equal(scenarios$thresholds$completion_rate, 0.8)
  expect_equal(scenarios$thresholds$preview_execution_distinction_rate, 0.8)
  expect_equal(scenarios$thresholds$median_sus, 75)
  expect_equal(scenarios$thresholds$maximum_minutes, 30)
  expect_identical(scenarios$thresholds$maximum_code_edits, 0L)
  expect_identical(scenarios$thresholds$maximum_raw_overwrites, 0L)
  expect_true(isTRUE(scenarios$human_evidence_required))
  workbook <- acceptance_path("staff", "facilitator-template.xlsx")
  expect_true(file.exists(workbook))
  wb <- suppressWarnings(openxlsx2::wb_load(workbook, data_only = FALSE))
  expect_setequal(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("说明", "场景记录", "区分测试", "SUS问卷", "签署", "评分摘要")
  )
})

test_that("statistician acceptance covers correctness and caveats", {
  scenarios <- yaml::read_yaml(
    acceptance_path("statistician", "scenarios.yml")
  )

  expect_gte(length(scenarios$scenarios), 8L)
  expect_true(isTRUE(scenarios$thresholds$all_correctness_assertions))
  expect_true(isTRUE(scenarios$thresholds$documented_caveats_required))
  ids <- vapply(scenarios$scenarios, `[[`, character(1), "id")
  expect_setequal(ids, c(
    "programmatic-import", "labelled-missing", "custom-rules",
    "preview-apply", "reproducibility", "full-table-export",
    "provenance", "legacy-migration"
  ))
})

test_that("agent suite has at least twenty bounded deterministic tasks", {
  suite <- jsonlite::read_json(
    acceptance_path("agent", "tasks.json"), simplifyVector = FALSE
  )

  expect_identical(suite$contract_version, "1.0")
  expect_gte(length(suite$tasks), 20L)
  ids <- vapply(suite$tasks, `[[`, character(1), "id")
  expect_identical(anyDuplicated(ids), 0L)
  for (task in suite$tasks) {
    expect_true(length(task$allowed_public_calls) > 0L, info = task$id)
    expect_true(task$max_attempts <= 2L, info = task$id)
    expect_true(!is.null(task$expected_stable_codes), info = task$id)
    expect_true(!is.null(task$artifact_assertions), info = task$id)
    expect_true(isTRUE(task$bounded_result), info = task$id)
    if (isTRUE(task$permits_execution)) {
      expect_true(isTRUE(task$requires_validation), info = task$id)
      expect_true(isTRUE(task$requires_preview), info = task$id)
    }
  }
  expect_equal(suite$thresholds$success_rate, 0.9)
  expect_identical(suite$thresholds$maximum_attempts, 2L)
})

test_that("agent task result schema is a closed contract", {
  path <- testthat::test_path(
    "..", "..", "inst", "schemas", "agent-task-result.schema.json"
  )
  schema <- jsonlite::read_json(path, simplifyVector = FALSE)

  expect_identical(schema$`$schema`, "https://json-schema.org/draft/2020-12/schema")
  expect_false(schema$additionalProperties)
  expect_setequal(
    unlist(schema$required),
    c(
      "contract_version", "task_id", "status", "attempts", "calls",
      "stable_codes", "artifacts", "result", "validated", "previewed"
    )
  )
})

test_that("acceptance runner preserves the human evidence boundary", {
  runner <- testthat::test_path("..", "..", "tools", "run-acceptance.R")
  expect_true(file.exists(runner))
  text <- paste(readLines(runner, warn = FALSE), collapse = "\n")

  expect_match(text, "facilitator_required", fixed = TRUE)
  expect_match(text, "human_evidence = FALSE", fixed = TRUE)
  expect_match(text, "--audience", fixed = TRUE)
})
