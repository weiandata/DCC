simple_findings <- function() {
  bind_findings(list(
    dcc_findings("S003", check_id = "Q_TRAP_ITEMS",
                 evidence = "failed 1 trap", severity = "fail"),
    dcc_findings("S002", variable = "score", check_id = "R001",
                 evidence = "value 150 outside range", severity = "fail"),
    dcc_findings("S001", variable = "q1", check_id = "R002",
                 evidence = "legacy code 9", severity = "warn")
  ))
}

test_that("dcc_execute applies exclude, set_na, recode and flag", {
  df <- fixture_responses()
  df$score[2] <- 150
  df$q1[1] <- 9
  res <- dcc_execute(
    df, simple_findings(),
    actions = list(
      Q_TRAP_ITEMS = "exclude",
      R001 = "set_na",
      R002 = list(action = "recode", map = c("9" = "5"))
    ),
    id_var = "sid"
  )
  expect_s3_class(res, "dcc_result")
  cleaned <- as.data.frame(dcc_cleaned(res))
  expect_false("S003" %in% cleaned$sid)
  expect_identical(res$n_excluded, 1L)
  expect_true(is.na(cleaned$score[cleaned$sid == "S002"]))
  expect_identical(cleaned$q1[cleaned$sid == "S001"], 5)

  log <- dcc_audit_log(res)
  expect_identical(nrow(log), 3L)
  expect_setequal(log$action, c("exclude", "set_na", "recode"))
  # cell-level lineage: old and new values recorded
  rec <- log[log$action == "recode", ]
  expect_identical(rec$old_value, "9")
  expect_identical(rec$new_value, "5")
  set_na_row <- log[log$action == "set_na", ]
  expect_identical(set_na_row$old_value, "150")
  expect_true(is.na(set_na_row$new_value))
})

test_that("unmapped findings get the default action (flag), not dropped", {
  df <- fixture_responses()
  res <- dcc_execute(df, simple_findings(), actions = list(),
                     id_var = "sid")
  log <- dcc_audit_log(res)
  expect_identical(nrow(log), 3L) # every finding produced a log row
  expect_identical(unique(log$action), "flag")
  expect_identical(res$n_excluded, 0L)
  expect_identical(nrow(as.data.frame(dcc_cleaned(res))), nrow(df))
})

test_that("closed loop: every audit row joins to a finding", {
  df <- fixture_responses()
  df$score[2] <- 150
  f <- simple_findings()
  res <- dcc_execute(df, f,
                     actions = list(Q_TRAP_ITEMS = "exclude",
                                    R001 = "set_na"),
                     id_var = "sid")
  log <- dcc_audit_log(res)
  joined <- merge(log, as.data.frame(f), by = "check_id")
  expect_identical(nrow(joined), nrow(log))
})

test_that("execute is immutable and provenance is appended", {
  x <- dcc_data(fixture_responses())
  f <- dcc_findings("1", variable = "q1", check_id = "C",
                    evidence = "e")
  res <- dcc_execute(x, f, actions = list(C = "set_na"))
  # input untouched
  expect_false(is.na(x$data$q1[1]))
  prov <- dcc_provenance(dcc_cleaned(res))
  expect_identical(prov$stage, c("create", "execute"))
  expect_identical(prov$details[[2]]$n_changes, 1L)
})

test_that("ruleset hash flows from detect into the audit log", {
  skip_if_not_installed("yaml")
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c("checks:",
               "  - id: R001",
               "    type: range",
               "    variable: score",
               "    min: 0",
               "    max: 100"), rules_file)
  df <- fixture_responses()
  df$score[2] <- 150
  x <- dcc_data(df)
  rs <- dcc_rules(rules_file)
  f <- dcc_detect(x, rs, id_var = "sid")
  res <- dcc_execute(x, f, actions = list(R001 = "set_na"),
                     id_var = "sid")
  expect_identical(unique(dcc_audit_log(res)$ruleset_hash), rs$hash)
})

test_that("execute errors are typed", {
  df <- fixture_responses()
  f <- dcc_findings("NOPE", check_id = "C", evidence = "e")
  expect_error(dcc_execute(df, f, actions = list(C = "exclude"),
                           id_var = "sid"),
               class = "dcc_execute_error")
  f2 <- dcc_findings("S001", check_id = "C", evidence = "e") # no variable
  expect_error(dcc_execute(df, f2, actions = list(C = "set_na"),
                           id_var = "sid"),
               class = "dcc_execute_error")
  expect_error(dcc_execute(df, f2, actions = list(C = "teleport"),
                           id_var = "sid"),
               class = "dcc_execute_error")
  expect_error(dcc_execute(df, data.frame(a = 1)),
               class = "dcc_type_error")
})

test_that("audit log exports to CSV (and Parquet when arrow present)", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C",
                    evidence = "e")
  res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
  csv <- tempfile(fileext = ".csv")
  dcc_export_log(res, csv, format = "csv")
  back <- data.table::fread(csv)
  expect_identical(nrow(back), 1L)
  expect_identical(back$check_id, "C")
  if (requireNamespace("arrow", quietly = TRUE)) {
    pq <- tempfile(fileext = ".parquet")
    dcc_export_log(res, pq)
    expect_true(file.exists(pq))
  }
})

test_that("print method runs", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C",
                    evidence = "e")
  res <- dcc_execute(df, f, actions = list(C = "flag"), id_var = "sid")
  expect_output(print(res), "dcc_result")
})

test_that("record-less (group-level) findings can be flagged", {
  df <- fixture_responses()
  f <- dcc_findings(NA_character_, variable = "score",
                    check_id = "Q_GROUP_SCORE_SHIFT",
                    evidence = "group (grp=B) mean shifted")
  res <- dcc_execute(df, f, id_var = "sid") # default flag
  log <- dcc_audit_log(res)
  expect_identical(nrow(log), 1L)
  expect_identical(log$action, "flag")
  expect_true(is.na(log$record_id))
  expect_identical(res$n_excluded, 0L)
})
