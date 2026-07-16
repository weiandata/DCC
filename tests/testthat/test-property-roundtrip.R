test_that("generated preview and apply paths reconcile deterministically", {
  for (seed in seq_len(100L)) {
    case <- generated_survey(seed)
    before <- case$data
    findings <- dcc_detect(case$data, case$rules, id_var = "sid")
    preview <- dcc_execute(
      case$data, findings, actions = list(), id_var = "sid"
    )
    active <- if (nrow(findings)) case$config$actions else list()
    applied <- dcc_execute(
      case$data, findings, actions = active, id_var = "sid"
    )
    reconciliation <- dcc_reconcile(applied)

    expect_seed_equal(nrow(preview$findings), nrow(findings), seed)
    expect_seed_equal(nrow(applied$findings), nrow(findings), seed)
    expect_seed_equal(
      sum(reconciliation$handled), nrow(dcc_audit_log(applied)), seed
    )
    expect_seed_equal(
      nrow(dcc_cleaned(applied)$data) + applied$n_excluded,
      nrow(case$data), seed
    )
    expect_seed_equal(case$data, before, seed)

    repeated_findings <- dcc_detect(case$data, case$rules, id_var = "sid")
    expect_seed_equal(
      repeated_findings$finding_id, findings$finding_id, seed
    )
    after_findings <- dcc_detect(
      dcc_cleaned(applied), case$rules, id_var = "sid"
    )
    expect_seed_equal(nrow(after_findings), 0L, seed)
  }
})

test_that("generated edge cases preserve semantics or fail explicitly", {
  cases <- generated_edge_cases()
  rules <- acceptance_ruleset()

  expect_equal(nrow(dcc_detect(cases$empty, rules, id_var = "sid")), 0L)
  expect_equal(nrow(dcc_detect(cases$all_missing, rules, id_var = "sid")), 0L)
  expect_equal(nrow(dcc_detect(cases$zero_match, rules, id_var = "sid")), 0L)
  expect_equal(nrow(dcc_detect(cases$extreme, rules, id_var = "sid")), 2L)

  labelled <- dcc_data(cases$labelled_missing)
  response <- labelled$data$response
  expect_identical(attr(response, "labels"), c(No = 1, Yes = 2))
  expect_true(haven::is_tagged_na(response[2L]))

  diagnostics <- dcc_l0_diagnose(cases$duplicate_names)
  expect_true("L0_DUPLICATE_COLNAME" %in% diagnostics$findings$check_id)
  expect_identical(as.character(cases$unicode$text), c("\u4e2d\u6587", "Espa\u00f1a"))
  expect_identical(as.character(cases$multiselect$choices), c("A|B", "B|C"))
})
