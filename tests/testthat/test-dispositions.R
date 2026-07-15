test_that("every finding has one terminal disposition", {
  f <- dcc_findings(c("S001", "S002"), variable = c("q1", "q2"),
                    check_id = c("C1", "C2"), evidence = c("e1", "e2"))
  res <- dcc_execute(fixture_responses(), f,
                     actions = list(C1 = "set_na", C2 = "flag"),
                     id_var = "sid")
  d <- dcc_dispositions(res)
  expect_identical(sort(d$finding_id), sort(res$findings$finding_id))
  expect_identical(anyDuplicated(d$finding_id), 0L)
  expect_true(all(d$status %in% c("changed", "excluded", "flagged",
                                  "skipped", "failed", "unhandled")))
  expect_identical(d$status, c("changed", "flagged"))
})

test_that("a cell action after record exclusion is explicitly skipped", {
  f <- dcc_findings(c("S001", "S001"), variable = c(NA, "q1"),
                    check_id = c("DROP", "CELL"), evidence = c("e1", "e2"))
  res <- dcc_execute(fixture_responses(), f,
                     actions = list(DROP = "exclude", CELL = "set_na"),
                     id_var = "sid")
  d <- dcc_dispositions(res)
  expect_identical(d$status, c("excluded", "skipped"))
  expect_match(d$message[2L], "already excluded")
  expect_identical(nrow(dcc_audit_log(res)), 1L)
})

test_that("dcc_dispositions rejects non-results", {
  expect_error(dcc_dispositions(data.frame()), class = "dcc_type_error")
})

test_that("provenance records stage outcome and boundaries", {
  rec <- new_provenance_record("detect", started_at = "a", ended_at = "b",
                               outcome = "success", hashes = list(rules = "h"),
                               counts = list(findings = 2L))
  expect_named(rec, c("stage", "started_at", "ended_at", "outcome",
                      "dcc_version", "hashes", "counts", "details"))

  prov <- dcc_provenance(dcc_data(fixture_df()))
  expect_named(prov, c("stage", "started_at", "ended_at", "outcome",
                       "dcc_version", "hashes", "counts", "details"))
})
