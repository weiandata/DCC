benchmark_tool <- dcc_source_path("tools", "check-benchmarks.R")

test_that("benchmark contract requires every pipeline and audience stage", {
  expect_true(file.exists(benchmark_tool))
  source(benchmark_tool, local = TRUE)

  expect_identical(
    benchmark_required_stages(),
    c(
      "import", "canonicalization", "validation", "detection", "preview",
      "execution", "report_model", "staff", "statistical", "machine"
    )
  )
})

test_that("benchmark comparator uses medians and rejects regressions", {
  source(benchmark_tool, local = TRUE)
  stages <- benchmark_required_stages()
  baseline <- data.frame(
    platform_class = "Darwin-arm64-R4.6", stage = stages,
    median_seconds = rep(10, length(stages)),
    peak_memory_bytes = rep(1e8, length(stages)), stringsAsFactors = FALSE
  )
  current <- do.call(rbind, lapply(seq_len(3L), function(run) {
    data.frame(
      platform_class = "Darwin-arm64-R4.6", run = run, stage = stages,
      seconds = rep(11, length(stages)), peak_memory_bytes = rep(1.1e8, length(stages)),
      correctness = TRUE,
      stringsAsFactors = FALSE
    )
  }))

  ok <- compare_benchmarks(current, baseline)
  expect_true(ok$ok)
  expect_equal(ok$comparison$relative_change, rep(0.1, length(stages)))

  current$seconds[current$stage == "detection"] <- 13
  regression <- compare_benchmarks(current, baseline)
  expect_false(regression$ok)
  expect_true("BENCHMARK_REGRESSION" %in% regression$failures$code)
})

test_that("benchmark comparator refuses incomplete or unlike evidence", {
  source(benchmark_tool, local = TRUE)
  stages <- benchmark_required_stages()
  baseline <- data.frame(
    platform_class = "Linux-x86_64-R4.6", stage = stages,
    median_seconds = rep(10, length(stages)),
    peak_memory_bytes = rep(1e8, length(stages)), stringsAsFactors = FALSE
  )
  current <- do.call(rbind, lapply(seq_len(3L), function(run) {
    data.frame(
      platform_class = "Linux-x86_64-R4.6", run = run, stage = stages,
      seconds = rep(10, length(stages)), peak_memory_bytes = rep(1e8, length(stages)),
      correctness = TRUE,
      stringsAsFactors = FALSE
    )
  }))

  missing <- compare_benchmarks(current[current$stage != "machine", ], baseline)
  expect_false(missing$ok)
  expect_true("BENCHMARK_STAGE_MISSING" %in% missing$failures$code)

  unlike <- current
  unlike$platform_class <- "Windows-x86_64-R4.6"
  mismatch <- compare_benchmarks(unlike, baseline)
  expect_false(mismatch$ok)
  expect_true("BENCHMARK_PLATFORM_MISMATCH" %in% mismatch$failures$code)
})

test_that("execution budget and minimum repetitions are hard gates", {
  source(benchmark_tool, local = TRUE)
  stages <- benchmark_required_stages()
  baseline <- data.frame(
    platform_class = "Linux-x86_64-R4.6", stage = stages,
    median_seconds = rep(40, length(stages)),
    peak_memory_bytes = rep(1e8, length(stages)), stringsAsFactors = FALSE
  )
  current <- do.call(rbind, lapply(seq_len(3L), function(run) {
    data.frame(
      platform_class = "Linux-x86_64-R4.6", run = run, stage = stages,
      seconds = ifelse(stages == "execution", 46, 40),
      peak_memory_bytes = rep(1e8, length(stages)), correctness = TRUE,
      stringsAsFactors = FALSE
    )
  }))

  over_budget <- compare_benchmarks(current, baseline)
  expect_false(over_budget$ok)
  expect_true("BENCHMARK_EXECUTION_BUDGET" %in% over_budget$failures$code)

  too_few <- compare_benchmarks(current[current$run != 3L, ], baseline)
  expect_false(too_few$ok)
  expect_true("BENCHMARK_RUNS_INSUFFICIENT" %in% too_few$failures$code)
})

test_that("accepted baseline records review rationale and memory ceilings", {
  source(benchmark_tool, local = TRUE)
  path <- dcc_source_path("tools", "benchmarks", "baseline.json")
  expect_true(file.exists(path))
  baseline <- jsonlite::read_json(path, simplifyVector = TRUE)

  expect_identical(baseline$contract_version, "1.0")
  expect_true(nzchar(baseline$update_reason))
  expect_true(isTRUE(baseline$review_required))
  expect_setequal(baseline$stages$stage, benchmark_required_stages())
  expect_true(all(baseline$stages$peak_memory_bytes > 0))
})

test_that("memory gate rejects undersized and unbounded evidence", {
  source(benchmark_tool, local = TRUE)
  memory_tool <- dcc_source_path("tools", "benchmarks", "memory.R")
  expect_true(file.exists(memory_tool))
  source(memory_tool, local = TRUE)
  records <- data.frame(
    stage = benchmark_required_stages(), rows = 1e6, columns = 25,
    input_bytes = 1e8, peak_memory_bytes = 5e8, correctness = TRUE,
    stringsAsFactors = FALSE
  )

  expect_true(check_memory_evidence(records)$ok)
  records$peak_memory_bytes[records$stage == "execution"] <- 9 * 1024^3
  excessive <- check_memory_evidence(records)
  expect_false(excessive$ok)
  expect_true("BENCHMARK_MEMORY_LIMIT" %in% excessive$failures$code)

  records$rows <- 1000
  undersized <- check_memory_evidence(records)
  expect_false(undersized$ok)
  expect_true("BENCHMARK_SCALE_INVALID" %in% undersized$failures$code)
})
