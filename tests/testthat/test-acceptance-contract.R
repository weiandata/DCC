acceptance_path <- function(...) {
  dcc_source_path("tests", "acceptance", ...)
}

test_that("staff acceptance supports one or more signed participants", {
  scenarios <- yaml::read_yaml(acceptance_path("staff", "scenarios.yml"))

  expect_identical(scenarios$contract_version, "1.0")
  expect_gte(length(scenarios$scenarios), 7L)
  expect_equal(scenarios$thresholds$completion_rate, 0.8)
  expect_equal(scenarios$thresholds$preview_execution_distinction_rate, 0.8)
  expect_equal(scenarios$thresholds$median_sus, 75)
  expect_equal(scenarios$thresholds$maximum_minutes, 30)
  expect_identical(scenarios$thresholds$maximum_code_edits, 0L)
  expect_identical(scenarios$thresholds$maximum_raw_overwrites, 0L)
  expect_identical(scenarios$thresholds$minimum_participants, 1L)
  expect_true(isTRUE(scenarios$human_evidence_required))
  workbook <- acceptance_path("staff", "facilitator-template.xlsx")
  expect_true(file.exists(workbook))
  wb <- suppressWarnings(openxlsx2::wb_load(workbook, data_only = FALSE))
  expect_setequal(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("说明", "场景记录", "区分测试", "SUS问卷", "签署", "评分摘要")
  )
})

test_that("staff release workbook is blank, signed-evidence gated, and complete", {
  workbook <- acceptance_path(
    "staff", "DCC-1.2.0-staff-acceptance.xlsx"
  )
  expect_true(file.exists(workbook))
  wb <- suppressWarnings(openxlsx2::wb_load(workbook, data_only = FALSE))
  expect_identical(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("说明", "参与者", "场景记录", "区分测试", "SUS问卷", "签署", "评分摘要")
  )

  signatures <- openxlsx2::wb_to_df(
    wb, sheet = "签署", rows = 6:10, cols = 2:7, col_names = FALSE
  )
  expect_true(all(is.na(signatures)))

  status <- openxlsx2::wb_to_df(
    wb, sheet = "评分摘要", rows = 20, cols = 5,
    col_names = FALSE
  )
  expect_identical(status[[1L]][1L], "facilitator_required")

  minimum <- openxlsx2::wb_to_df(
    wb, sheet = "评分摘要", rows = 5, cols = 3,
    col_names = FALSE
  )
  expect_identical(minimum[[1L]][1L], 1)
})

test_that("staff test kit sources include a complete safe R workflow and manual", {
  script <- acceptance_path("staff", "staff-test.R")
  manual <- acceptance_path("staff", "staff-test-manual-zh-CN.md")
  expect_true(file.exists(script))
  expect_true(file.exists(manual))

  code <- paste(readLines(script, warn = FALSE), collapse = "\n")
  expect_match(code, "AUTHORIZE_EXECUTION <- FALSE", fixed = TRUE)
  expect_match(code, "dcc_check(", fixed = TRUE)
  expect_match(code, 'mode = "preview"', fixed = TRUE)
  expect_match(code, 'mode = "execute"', fixed = TRUE)
  expect_match(code, "sha256sum", fixed = TRUE)
  expect_match(code, "dependencies = c(\"Depends\", \"Imports\", \"LinkingTo\")",
               fixed = TRUE)

  text <- paste(readLines(manual, warn = FALSE), collapse = "\n")
  expect_match(text, "至少 1 名", fixed = TRUE)
  expect_match(text, "不阻断 DCC 包发布", fixed = TRUE)
  expect_match(text, "AUTHORIZE_EXECUTION", fixed = TRUE)
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
  path <- dcc_source_path("inst", "schemas", "agent-task-result.schema.json")
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

test_that("agent execution scoring blocks calls outside the task whitelist", {
  tool <- dcc_source_path("tools", "agent-acceptance.R")
  expect_true(file.exists(tool))
  source(tool, local = TRUE)
  task <- list(
    id = "T01", category = "discovery", prompt = "Discover.",
    allowed_public_calls = list("dcc_capabilities"),
    expected_stable_codes = list(), artifact_assertions = list(),
    max_attempts = 1L, bounded_result = TRUE, permits_execution = FALSE,
    requires_validation = FALSE, requires_preview = FALSE
  )
  suite <- list(
    tasks = list(task),
    thresholds = list(success_rate = 0.9, maximum_attempts = 2L)
  )
  good <- agent_task_result(
    task_id = "T01", calls = "dcc_capabilities",
    result = list(executed = FALSE)
  )
  expect_true(agent_score_results(suite, list(good))$ok)
  path <- tempfile(fileext = ".json")
  agent_write_task_result(good, path)
  serialized <- jsonlite::read_json(path, simplifyVector = FALSE)
  expect_type(serialized$calls, "list")
  expect_length(serialized$calls, 1L)
  expect_type(serialized$stable_codes, "list")
  expect_length(serialized$stable_codes, 0L)
  expect_true(agent_score_results(suite, list(serialized))$ok)

  unsafe <- good
  unsafe$calls <- c("dcc_capabilities", "system")
  score <- agent_score_results(suite, list(unsafe))
  expect_false(score$ok)
  expect_true("CALL_OUTSIDE_WHITELIST" %in% score$failures$code)
})

test_that("acceptance runner preserves the human evidence boundary", {
  runner <- dcc_source_path("tools", "run-acceptance.R")
  expect_true(file.exists(runner))
  text <- paste(readLines(runner, warn = FALSE), collapse = "\n")

  expect_match(text, "facilitator_required", fixed = TRUE)
  expect_match(text, "human_evidence = FALSE", fixed = TRUE)
  expect_match(text, "--audience", fixed = TRUE)
  expect_match(text, "agent-acceptance.R", fixed = TRUE)
  expect_match(text, "mode, \"execute\"", fixed = TRUE)
})
