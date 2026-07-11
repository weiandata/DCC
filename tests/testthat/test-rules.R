write_rules <- function(text) {
  f <- tempfile(fileext = ".yaml")
  writeLines(text, f, useBytes = TRUE)
  f
}

test_that("dcc_rules loads and validates a rule file", {
  skip_if_not_installed("yaml")
  f <- write_rules('
checks:
  - id: R001
    type: range
    variable: score
    min: 0
    max: 100
  - id: R002
    type: set
    variable: grp
    values: [A, B]
')
  rs <- dcc_rules(f)
  expect_s3_class(rs, "dcc_ruleset")
  expect_length(rs$checks, 2L)
  expect_true(nzchar(rs$hash))
  expect_output(print(rs), "R001")
})

test_that("dcc_rules rejects malformed files", {
  skip_if_not_installed("yaml")
  expect_error(dcc_rules(tempfile()), class = "dcc_io_error")
  expect_error(dcc_rules(write_rules("other: 1")),
               class = "dcc_rule_error")
  expect_error(dcc_rules(write_rules('
checks:
  - id: X
    type: range
  - id: X
    type: range
')), class = "dcc_rule_error")
})

test_that("range and set checks flag violations", {
  skip_if_not_installed("yaml")
  df <- fixture_responses()
  df$score[2] <- 150
  df$grp[3] <- "Z"
  rs <- dcc_rules(write_rules('
checks:
  - id: R001
    type: range
    variable: score
    min: 0
    max: 100
    severity: fail
  - id: R002
    type: set
    variable: grp
    values: [A, B]
'))
  f <- dcc_detect(df, rs, id_var = "sid")
  expect_identical(f$record_id[f$check_id == "R001"], "S002")
  expect_identical(f$severity[f$check_id == "R001"], "fail")
  expect_identical(f$record_id[f$check_id == "R002"], "S003")
  expect_identical(unique(f$dimension), "validity")
})

test_that("expr checks evaluate in a restricted environment", {
  skip_if_not_installed("yaml")
  df <- fixture_responses()
  rs <- dcc_rules(write_rules('
checks:
  - id: E001
    type: expr
    expr: "time_total < 60 & score > 0"
'))
  f <- dcc_detect(df, rs, id_var = "sid")
  expect_identical(f$record_id, "S003")

  # I/O and unknown functions are not reachable
  rs_bad <- dcc_rules(write_rules('
checks:
  - id: E002
    type: expr
    expr: "file.exists(\'x\')"
'))
  expect_error(dcc_detect(df, rs_bad, id_var = "sid"),
               class = "dcc_rule_error")
})

test_that("detector checks run from YAML config", {
  skip_if_not_installed("yaml")
  df <- fixture_responses()
  rs <- dcc_rules(write_rules('
checks:
  - id: D001
    type: straightlining
    items: [q1, q2, q3, q4, q5, q6, q7, q8, q9, q10]
    max_run: 10
  - id: D002
    type: trap_items
    traps:
      trap1: 3
'))
  f <- dcc_detect(df, rs, id_var = "sid")
  expect_identical(f$record_id[f$check_id == "Q_STRAIGHTLINING"], "S003")
  expect_setequal(f$record_id[f$check_id == "Q_TRAP_ITEMS"],
                  c("S003", "S007"))
})

test_that("unknown check types are typed errors", {
  skip_if_not_installed("yaml")
  rs <- dcc_rules(write_rules('
checks:
  - id: B001
    type: teleport
'))
  expect_error(dcc_detect(fixture_responses(), rs),
               class = "dcc_rule_error")
})

test_that("dcc_detect on dcc_data appends detect provenance", {
  skip_if_not_installed("yaml")
  x <- dcc_data(fixture_responses())
  rs <- dcc_rules(write_rules('
checks:
  - id: R001
    type: range
    variable: score
    min: 0
    max: 100
'))
  f <- dcc_detect(x, rs, id_var = "sid")
  x2 <- attr(f, "dcc_data")
  expect_s3_class(x2, "dcc_data")
  prov <- dcc_provenance(x2)
  expect_identical(prov$stage, c("create", "detect"))
  expect_identical(prov$details[[2]]$ruleset_hash, rs$hash)
  # input object untouched (detection is pure)
  expect_identical(length(x$provenance), 1L)
})

test_that("detection is deterministic", {
  skip_if_not_installed("yaml")
  df <- fixture_responses()
  rs <- dcc_rules(write_rules('
checks:
  - id: D001
    type: missing_items
    items: [q1, q2, q3, q4, q5, q6, q7, q8, q9, q10]
    max_prop: 0.3
'))
  f1 <- dcc_detect(df, rs, id_var = "sid")
  f2 <- dcc_detect(df, rs, id_var = "sid")
  expect_identical(as.data.frame(f1), as.data.frame(f2))
})
