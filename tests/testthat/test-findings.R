test_that("dcc_findings builds and validates", {
  f <- dcc_findings(
    record_id = c("S1", "S2"),
    check_id = "CHK",
    evidence = c("a", "b"),
    severity = "warn",
    dimension = "validity"
  )
  expect_s3_class(f, "dcc_findings")
  expect_identical(nrow(f), 2L)
  expect_identical(names(f),
                   c("finding_id", "record_id", "variable", "check_id", "evidence",
                     "severity", "dimension", "code", "detector_id"))
  expect_error(dcc_findings("S1", check_id = "C", evidence = "e",
                            severity = "catastrophic"),
               class = "dcc_type_error")
})

test_that("findings expose stable code and detector identity", {
  f <- dcc_findings("S1", "q1", "R001", "bad",
                    code = "OUT_OF_RANGE", detector_id = "range")
  expect_identical(f$code, "OUT_OF_RANGE")
  expect_identical(f$detector_id, "range")

  legacy <- dcc_findings("S1", "q1", "Q_TRAP_ITEMS", "bad")
  expect_identical(legacy$code, "Q_TRAP_ITEMS")
  expect_identical(legacy$detector_id, "Q_TRAP_ITEMS")
})

test_that("empty findings and binding work", {
  e <- dcc_findings()
  expect_identical(nrow(e), 0L)
  expect_s3_class(e, "dcc_findings")

  f <- dcc_findings("S1", check_id = "C", evidence = "e")
  b <- bind_findings(list(e, f, NULL))
  expect_identical(nrow(b), 1L)
  expect_s3_class(b, "dcc_findings")
})

test_that("findings receive deterministic IDs with occurrence suffixes", {
  f <- dcc_findings(
    record_id = c("S1", "S1", "S2"),
    variable = c("q1", "q1", "q1"),
    check_id = c("R1", "R1", "R1"),
    evidence = c("a", "b", "c"),
    run_id = "run-42"
  )
  expect_identical(
    f$finding_id,
    c("6:run-42|2:R1|2:S1|2:q1|0", "6:run-42|2:R1|2:S1|2:q1|1",
      "6:run-42|2:R1|2:S2|2:q1|0")
  )
  expect_identical(dcc_findings("S1", check_id = "R1", evidence = "a")$finding_id,
                   "6:manual|2:R1|2:S1|8:<record>|0")
  expect_identical(names(dcc_findings()),
                   c("finding_id", "record_id", "variable", "check_id",
                     "evidence", "severity", "dimension", "code",
                     "detector_id"))
})

test_that("binding regenerates collision-safe IDs within a run", {
  a <- dcc_findings("S1", variable = "q1", check_id = "R1", evidence = "a")
  b <- dcc_findings("S1", variable = "q1", check_id = "R1", evidence = "b")
  bound <- bind_findings(list(a, b))
  expect_identical(anyDuplicated(bound$finding_id), 0L)

  left <- dcc_findings("S1", variable = "q1", check_id = "a|b",
                       evidence = "x", run_id = "run")
  right <- dcc_findings("b|S1", variable = "q1", check_id = "a",
                        evidence = "x", run_id = "run")
  expect_false(identical(left$finding_id, right$finding_id))
})

test_that("print method runs", {
  f <- dcc_findings("S1", check_id = "C", evidence = "e")
  expect_output(print(f), "1 finding")
  expect_output(print(dcc_findings()), "0 finding")
})
