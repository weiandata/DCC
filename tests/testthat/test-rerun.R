pipeline_fixture <- function() {
  skip_if_not_installed("yaml")
  data_file <- tempfile(fileext = ".csv")
  df <- fixture_responses()
  df$score[2] <- 150
  data.table::fwrite(df, data_file)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c("checks:",
               "  - id: R001",
               "    type: range",
               "    variable: score",
               "    min: 0",
               "    max: 100",
               "  - id: D001",
               "    type: trap_items",
               "    traps:",
               "      trap1: 3"), rules_file)
  x <- dcc_read(data_file)
  rules <- dcc_rules(rules_file)
  findings <- dcc_detect(x, rules, id_var = "sid")
  result <- dcc_execute(x, findings,
                        actions = list(R001 = "set_na",
                                       D001 = "exclude"),
                        id_var = "sid")
  list(data_file = data_file, rules_file = rules_file, result = result)
}

test_that("manifest captures sources, hashes and actions", {
  p <- pipeline_fixture()
  m <- dcc_manifest(p$result)
  expect_s3_class(m, "dcc_manifest")
  expect_identical(m$contract_version, "1.2")
  expect_identical(m$input$file_hash,
                   unname(tools::md5sum(p$data_file)))
  expect_identical(m$ruleset$hash,
                   unname(tools::md5sum(p$rules_file)))
  expect_identical(m$id_var, "sid")
  expect_identical(m$actions$R001, "set_na")
  expect_true(nzchar(m$output$data_hash))
})

test_that("rerun reproduces the pipeline byte-identically", {
  p <- pipeline_fixture()
  rr <- dcc_rerun(p$result)
  expect_true(rr$reproduced)
  expect_true(rr$data_match)
  expect_true(rr$audit_match)
  expect_output(print(rr), "reproduced: TRUE")
})

test_that("rerun works from a manifest YAML file", {
  p <- pipeline_fixture()
  mf <- tempfile(fileext = ".yaml")
  dcc_manifest(p$result, path = mf)
  expect_true(file.exists(mf))
  rr <- dcc_rerun(mf)
  expect_true(rr$reproduced)
})

test_that("changed inputs are typed errors, not false reproductions", {
  p <- pipeline_fixture()
  m <- dcc_manifest(p$result)
  # tamper with the raw data
  df <- data.table::fread(p$data_file)
  df$score[1] <- 999
  data.table::fwrite(df, p$data_file)
  expect_error(dcc_rerun(m), class = "dcc_rerun_error")
})

test_that("changed rules are typed errors", {
  p <- pipeline_fixture()
  m <- dcc_manifest(p$result)
  writeLines(c("checks:",
               "  - id: R001",
               "    type: range",
               "    variable: score",
               "    min: 0",
               "    max: 90"), p$rules_file)
  expect_error(dcc_rerun(m), class = "dcc_rerun_error")
})

test_that("results without read/detect provenance refuse a manifest", {
  df <- fixture_responses()
  f <- dcc_findings("S001", variable = "q1", check_id = "C",
                    evidence = "e")
  res <- dcc_execute(df, f, actions = list(C = "flag"), id_var = "sid")
  expect_error(dcc_manifest(res), class = "dcc_manifest_error")
})
