test_that("execution retains a reporting input profile without raw rows", {
  result <- report_result_fixture()

  expect_named(result$report_profile,
               c("rows", "missingness", "distributions", "types"))
  expect_equal(result$report_profile$rows, 3L)
  expect_false(any(vapply(result$report_profile, inherits, logical(1),
                          "dcc_data")))
  score <- result$report_profile$distributions
  score <- score[score$variable == "score", , drop = FALSE]
  expect_setequal(score$value, c("70", "90", "150"))
})

test_that("report model contains complete before and after profiles", {
  model <- report_model_fixture()

  expect_true(all(c("missingness", "distributions", "types") %in%
                    names(model$summaries)))
  expect_setequal(unique(model$summaries$distributions$stage),
                  c("before", "after"))
  totals <- data.table::as.data.table(model$summaries$distributions)[
    , list(total = sum(count)), by = c("stage", "variable")
  ]
  expect_true(all(totals$total[totals$stage == "before"] == 3L))
  expect_true(all(totals$total[totals$stage == "after"] == 2L))
})

test_that("statistical bundle contains complete tables and metadata", {
  out <- withr::local_tempdir()
  model <- report_model_fixture()
  files <- dcc_report_statistical(model, out, table_format = "csv")

  expect_true(all(c(
    "statistical-report.html", "findings.csv", "audit-log.csv",
    "reconciliation.csv", "missingness.csv", "distributions.csv",
    "types.csv", "scoring.csv", "mapping.csv", "provenance.json",
    "parameters.json", "artifact-manifest.json"
  ) %in% basename(files)))
  findings <- data.table::fread(file.path(out, "findings.csv"))
  expect_equal(nrow(findings), nrow(model$findings))
  distributions <- data.table::fread(file.path(out, "distributions.csv"))
  expect_equal(nrow(distributions), nrow(model$summaries$distributions))
})

test_that("statistical artifact manifest records reproducible SHA-256 hashes", {
  out <- withr::local_tempdir()
  files <- dcc_report_statistical(report_model_fixture(), out,
                                  table_format = "csv")
  manifest_path <- files[basename(files) == "artifact-manifest.json"]
  manifest <- jsonlite::fromJSON(manifest_path)

  expect_identical(manifest$contract_version, "1.0")
  expect_false("artifact-manifest.json" %in% manifest$artifacts$path)
  expect_true(all(grepl("^[0-9a-f]{64}$", manifest$artifacts$sha256)))
  actual <- unname(tools::sha256sum(
    file.path(out, manifest$artifacts$path)
  ))
  expect_identical(actual, manifest$artifacts$sha256)
})

test_that("statistical bundle writes full Parquet tables", {
  out <- withr::local_tempdir()
  model <- report_model_fixture()
  files <- dcc_report_statistical(model, out, table_format = "parquet",
                                  html = FALSE)

  expect_false("statistical-report.html" %in% basename(files))
  expect_true("findings.parquet" %in% basename(files))
  findings <- arrow::read_parquet(file.path(out, "findings.parquet"),
                                  as_data_frame = TRUE)
  expect_equal(nrow(findings), nrow(model$findings))
})

test_that("statistical narrative states methods, denominators, and caveats", {
  out <- withr::local_tempdir()
  files <- dcc_report_statistical(report_model_fixture(), out,
                                  table_format = "csv")
  html <- paste(readLines(
    files[basename(files) == "statistical-report.html"], warn = FALSE
  ), collapse = "\n")

  expect_match(html, "Methods")
  expect_match(html, "Denominators")
  expect_match(html, "Missing-value semantics")
  expect_match(html, "Caveats")
  expect_match(html, "ruleset")
  expect_match(html, "R version")
})
