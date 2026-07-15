report_result <- function() {
  df <- fixture_responses()
  df$score[2] <- 150
  f <- bind_findings(list(
    dcc_findings("S002", variable = "score", check_id = "R001",
                 evidence = "value 150 outside range",
                 severity = "fail", dimension = "validity"),
    dcc_findings("S003", check_id = "Q_TRAP_ITEMS",
                 evidence = "failed trap", severity = "fail",
                 dimension = "accuracy")
  ))
  dcc_execute(df, f,
              actions = list(R001 = "set_na", Q_TRAP_ITEMS = "exclude"),
              id_var = "sid")
}

test_that("summary report renders and contains the key sections", {
  res <- report_result()
  path <- tempfile(fileext = ".html")
  html <- dcc_report(res, path)
  expect_true(file.exists(path))
  expect_match(html, "DCC cleaning report \\(summary\\)")
  expect_match(html, "Findings by quality dimension")
  expect_match(html, "validity")
  expect_match(html, "exclude")
  # summary layer must not embed the cell-level log
  expect_no_match(html, "Cell-level change log")
})

test_that("audit report embeds reconciliation and the change log", {
  res <- report_result()
  html <- dcc_report(res, audience = "audit")
  expect_match(html, "Findings-to-changes reconciliation")
  expect_match(html, "2 of 2 finding\\(s\\) handled")
  expect_match(html, "Cell-level change log")
  expect_match(html, "S002")
})

test_that("audit report caps embedded log rows", {
  res <- report_result()
  html <- dcc_report(res, audience = "audit", max_rows = 1L)
  expect_match(html, "showing first 1 of 2 rows")
})

test_that("HTML output is escaped", {
  df <- data.frame(sid = "S1", q1 = "<script>")
  f <- dcc_findings("S1", variable = "q1", check_id = "C<h1>",
                    evidence = "evil <tag>")
  res <- dcc_execute(df, f, actions = list(`C<h1>` = "flag"),
                     id_var = "sid")
  html <- dcc_report(res, audience = "audit")
  expect_no_match(html, "evil <tag>", fixed = TRUE)
  expect_match(html, "evil &lt;tag&gt;", fixed = TRUE)
})

test_that("reconciliation uses exact finding IDs and exposes unhandled rows", {
  f <- dcc_findings(c("S001", "S001"), variable = c("q1", "q1"),
                    check_id = c("C", "C"), evidence = c("first", "second"))
  res <- dcc_execute(fixture_responses(), f, actions = list(C = "flag"),
                     id_var = "sid")
  rec <- dcc_reconcile(res)
  expect_identical(rec$status, c("flagged", "flagged"))
  expect_setequal(rec$finding_id, f$finding_id)

  # an audit row that joins to no finding is an integrity failure
  res$audit$finding_id[1] <- "missing-id"
  expect_error(dcc_reconcile(res), class = "dcc_reconcile_error")

  # with no actions every finding is terminally unhandled
  unresolved <- dcc_execute(fixture_responses(), f, actions = list(),
                            id_var = "sid")
  expect_identical(dcc_reconcile(unresolved)$status,
                   c("unhandled", "unhandled"))
})

test_that("a lost audit row is a reconciliation integrity error", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C", evidence = "e")
  res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
  expect_identical(dcc_reconcile(res)$status, "changed")
  # simulate a dropped audit row: terminal disposition and evidence disagree
  res$audit <- res$audit[0L]
  expect_error(dcc_reconcile(res), class = "dcc_reconcile_error")
})

test_that("dcc_trace returns the cell history", {
  res <- report_result()
  tr <- dcc_trace(res, "S002", "score")
  expect_s3_class(tr, "dcc_trace")
  expect_identical(nrow(tr$findings), 1L)
  expect_identical(nrow(tr$changes), 1L)
  expect_identical(tr$changes$old_value, "150")
  expect_true(is.na(tr$changes$new_value))
  expect_output(print(tr), "record 'S002'")

  # record-level trace without variable
  tr2 <- dcc_trace(res, "S003")
  expect_identical(nrow(tr2$findings), 1L)
  # unknown record: empty but valid
  tr3 <- dcc_trace(res, "S999")
  expect_identical(nrow(tr3$findings), 0L)
  expect_identical(nrow(tr3$changes), 0L)
})
