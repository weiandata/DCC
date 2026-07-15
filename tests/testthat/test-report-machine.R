test_that("machine bundle has deterministic paths and versioned schemas", {
  out <- withr::local_tempdir()
  files <- dcc_report_machine(report_model_fixture(), out)

  expect_setequal(
    basename(files),
    c("run.json", "validation.json", "summary.json", "findings.jsonl",
      "audit-log.jsonl", "reconciliation.jsonl", "provenance.json",
      "manifest.json", "schemas")
  )
  expect_setequal(
    list.files(file.path(out, "schemas")),
    c("run.schema.json", "validation.schema.json", "summary.schema.json",
      "finding.schema.json", "audit-record.schema.json",
      "reconciliation.schema.json", "provenance.schema.json",
      "artifact-manifest.schema.json")
  )
})

test_that("machine JSON and JSONL artifacts validate without jsonvalidate", {
  out <- withr::local_tempdir()
  dcc_report_machine(report_model_fixture(), out)

  expect_true(dcc_validate_json(file.path(out, "run.json"), "run"))
  expect_true(dcc_validate_json(file.path(out, "validation.json"),
                                "validation"))
  expect_true(dcc_validate_json(file.path(out, "summary.json"), "summary"))
  expect_true(dcc_validate_json(file.path(out, "provenance.json"),
                                "machine_provenance"))
  expect_true(dcc_validate_json(file.path(out, "manifest.json"),
                                "artifact_manifest"))
  expect_true(dcc_validate_jsonl(file.path(out, "findings.jsonl"),
                                 "finding"))
  expect_true(dcc_validate_jsonl(file.path(out, "audit-log.jsonl"),
                                 "audit_record"))
  expect_true(dcc_validate_jsonl(file.path(out, "reconciliation.jsonl"),
                                 "reconciliation"))
})

test_that("machine JSONL contains every complete model row", {
  out <- withr::local_tempdir()
  model <- report_model_fixture()
  dcc_report_machine(model, out)

  expect_length(readLines(file.path(out, "findings.jsonl")),
                nrow(model$findings))
  expect_length(readLines(file.path(out, "audit-log.jsonl")),
                nrow(model$changes))
  expect_length(readLines(file.path(out, "reconciliation.jsonl")),
                nrow(model$reconciliation))
})

test_that("compact AI summary is bounded, deterministic, and action oriented", {
  result <- report_result_fixture(secret = "ID-123-sensitive")
  first <- dcc_result_summary(result, detail = "compact")
  second <- dcc_result_summary(result, detail = "compact")

  expect_named(first, c("status", "counts", "top_findings", "artifacts",
                        "next_actions"))
  expect_lte(nrow(first$top_findings), 20L)
  expect_identical(first, second)
  expect_false("evidence" %in% names(first$top_findings))
  expect_false(any(grepl("ID-123-sensitive", unlist(first), fixed = TRUE)))
  expect_true(is.character(first$next_actions))
})

test_that("full AI summary remains structured and reconciled", {
  result <- report_result_fixture()
  full <- dcc_result_summary(result, detail = "full")

  expect_true(all(c("reconciliation", "provenance", "hashes") %in%
                    names(full)))
  expect_equal(full$counts$findings_total, nrow(full$reconciliation))
  expect_true(is.data.frame(full$reconciliation))
})

test_that("JSON validation rejects malformed or contract-invalid files", {
  malformed <- tempfile(fileext = ".json")
  writeLines("{", malformed)
  expect_false(dcc_validate_json(malformed, "summary"))

  invalid <- tempfile(fileext = ".json")
  jsonlite::write_json(list(contract_version = "wrong"), invalid,
                       auto_unbox = TRUE)
  expect_false(dcc_validate_json(invalid, "summary"))
})
