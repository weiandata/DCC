chunk_fixture <- function() {
  skip_if_not_installed("yaml")
  df <- fixture_responses()
  df$score[2] <- 150
  csv <- tempfile(fileext = ".csv")
  data.table::fwrite(df, csv)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    min: 0",
    "    max: 100",
    "  - id: D001",
    "    type: straightlining",
    "    items: [q1, q2, q3, q4, q5, q6, q7, q8, q9, q10]",
    "    max_run: 10",
    "  - id: D002",
    "    type: trap_items",
    "    traps:",
    "      trap1: 3",
    "  - id: D003",
    "    type: response_time",
    "    time_var: time_total",
    "    min_seconds: 60",
    "    min_median_ratio: ~"
  ), rules_file)
  list(csv = csv, rules = dcc_rules(rules_file))
}

normalize_findings <- function(f) {
  d <- as.data.frame(f)[order(f$record_id, f$check_id), ]
  rownames(d) <- NULL
  d
}

test_that("chunked findings equal in-memory findings", {
  fx <- chunk_fixture()
  in_mem <- dcc_detect(dcc_read(fx$csv), fx$rules, id_var = "sid")
  # chunk smaller / straddling / exact multiple / larger than the file
  for (cs in c(3L, 5L, 4L, 100L)) {
    chunked <- dcc_detect_chunked(fx$csv, fx$rules, chunk_size = cs,
                                  id_var = "sid")
    expect_identical(normalize_findings(chunked),
                     normalize_findings(in_mem),
                     label = paste("chunk_size", cs))
  }
})

test_that("chunked row-number ids are globally consistent", {
  fx <- chunk_fixture()
  chunked <- dcc_detect_chunked(fx$csv, fx$rules, chunk_size = 3L)
  in_mem <- dcc_detect(dcc_read(fx$csv), fx$rules)
  expect_setequal(chunked$record_id, in_mem$record_id)
  expect_identical(attr(chunked, "n_rows", exact = TRUE), 8L)
  expect_identical(attr(chunked, "n_chunks", exact = TRUE), 3L)
})

test_that("cross-record checks are rejected with typed errors", {
  fx <- chunk_fixture()
  bad_rules <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: S001",
    "    type: score_anomaly",
    "    score_var: score"
  ), bad_rules)
  expect_error(
    dcc_detect_chunked(fx$csv, dcc_rules(bad_rules)),
    class = "dcc_chunk_error"
  )

  rel_time <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: T001",
    "    type: response_time",
    "    time_var: time_total",
    "    min_seconds: 60"
  ), rel_time) # median cut not disabled
  expect_error(
    dcc_detect_chunked(fx$csv, dcc_rules(rel_time)),
    class = "dcc_chunk_error"
  )
})

test_that("chunked input validation is typed", {
  fx <- chunk_fixture()
  expect_error(dcc_detect_chunked("no-such.csv", fx$rules),
               class = "dcc_io_error")
  expect_error(dcc_detect_chunked(fx$csv, data.frame(a = 1)),
               class = "dcc_type_error")
  expect_error(dcc_detect_chunked(fx$csv, fx$rules, id_var = "nope"),
               class = "dcc_type_error")
})

test_that("explicitly disabled median cut still works in memory", {
  fx <- chunk_fixture()
  f <- dcc_detect(dcc_read(fx$csv), fx$rules, id_var = "sid")
  # D003 has min_median_ratio disabled: only S003 (40s < 60s absolute)
  rt <- f[f$check_id == "Q_RESPONSE_TIME", ]
  expect_identical(rt$record_id, "S003")
})
