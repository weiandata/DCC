test_that("dcc_schema returns installed schema files", {
  for (nm in c("finding", "disposition", "provenance", "audit_log", "rules",
               "actions", "manifest")) {
    p <- dcc_schema(nm, as = "path")
    expect_true(file.exists(p), info = nm)
  }
})

test_that("published schemas match the objects the package produces", {
  skip_if_not_installed("jsonlite")

  # a finding row: required fields equal the dcc_findings columns
  fs <- dcc_schema("finding")
  f <- dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e")
  expect_setequal(fs$required, names(f))
  expect_identical(fs$type, "object")

  # an audit-log row: required fields equal the audit-log columns
  as_schema <- dcc_schema("audit_log")
  res <- dcc_execute(
    data.frame(sid = "S1", q1 = 9),
    dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e"),
    actions = list(C = "set_na"), id_var = "sid"
  )
  expect_setequal(as_schema$required, names(dcc_audit_log(res)))

  # a rule set: describes a `checks` array whose items require id + type
  rs <- dcc_schema("rules")
  expect_true("checks" %in% names(rs$properties))
  expect_setequal(rs$properties$checks$items$required, c("id", "type"))

  # an action map is an object; a manifest schema is installed
  expect_identical(dcc_schema("actions")$type, "object")
  expect_true(file.exists(dcc_schema("manifest", as = "path")))

  ds <- dcc_schema("disposition")
  expect_setequal(ds$required,
                  c("finding_id", "action", "status", "message"))
  expect_setequal(ds$properties$status$enum,
                  c("changed", "excluded", "flagged", "skipped", "failed",
                    "unhandled"))

  ps <- dcc_schema("provenance")
  expect_setequal(ps$required,
                  c("stage", "started_at", "ended_at", "outcome",
                    "dcc_version", "hashes", "counts", "details"))
})

test_that("dcc_schema rejects an unknown schema name", {
  expect_error(dcc_schema("nope"))
})
