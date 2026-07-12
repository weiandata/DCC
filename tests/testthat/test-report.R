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
  expect_match(html, "unreconciled changes: 0")
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

test_that("dcc_reconcile flags unhandled findings", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C",
                    evidence = "e")
  res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
  rec <- dcc_reconcile(res)
  expect_true(all(rec$handled))
  expect_identical(attr(rec, "unreconciled_changes"), 0L)

  # simulate a lost log: strip the audit table
  res$audit <- res$audit[0L]
  rec2 <- dcc_reconcile(res)
  expect_false(any(rec2$handled))
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
