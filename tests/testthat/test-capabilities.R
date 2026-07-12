test_that("dcc_capabilities exposes the documented contract", {
  caps <- dcc_capabilities()
  expect_identical(
    names(caps),
    c("contract_version", "package_version", "features",
      "rule_types", "action_types", "formats", "unsupported")
  )
  expect_type(caps$contract_version, "character")
  expect_identical(caps$package_version,
                   as.character(utils::packageVersion("DCC")))

  expect_s3_class(caps$features, "data.frame")
  expect_identical(names(caps$features), c("name", "status", "since"))
  expect_true(all(caps$features$status %in%
                    c("Stable", "Experimental", "Planned")))

  expect_identical(caps$action_types,
                   c("exclude", "set_na", "flag", "recode"))
  expect_true(all(c("range", "set", "expr", "missing_items",
                    "straightlining", "response_time", "trap_items",
                    "score_anomaly") %in% caps$rule_types))
  expect_identical(sort(caps$formats$format),
                   sort(c("csv", "tsv", "excel", "spss", "stata", "sas",
                          "parquet", "feather", "json")))
})

test_that("advertised action types match the execute validator", {
  df <- data.frame(sid = "S1", q1 = 1)
  # every non-recode action the contract advertises is accepted
  for (act in setdiff(dcc_capabilities()$action_types, "recode")) {
    f <- dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e")
    expect_error(
      dcc_execute(df, f, actions = stats::setNames(list(act), "C"),
                  id_var = "sid"),
      NA
    )
  }
  # an action absent from the contract is rejected
  f <- dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e")
  expect_error(
    dcc_execute(df, f, actions = list(C = "teleport"), id_var = "sid"),
    class = "dcc_execute_error"
  )
})
