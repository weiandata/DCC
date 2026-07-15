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
  # finding_id embeds the run prefix (rule + source-file hash), so it
  # legitimately differs between two physical files (e.g. a CSV and its
  # Parquet copy). Determinism from a single source is covered in
  # test-rules; here we compare only the substantive finding columns.
  d$finding_id <- NULL
  rownames(d) <- NULL
  # Drop object-level attributes (dcc_data, n_rows, n_chunks, backend,
  # ...) so comparisons are on the finding rows only.
  for (a in setdiff(names(attributes(d)),
                    c("names", "row.names", "class"))) {
    attr(d, a) <- NULL
  }
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

test_that("auto backend records which backend ran", {
  fx <- chunk_fixture()
  chunked <- dcc_detect_chunked(fx$csv, fx$rules, chunk_size = 5L,
                                id_var = "sid")
  expect_identical(attr(chunked, "backend", exact = TRUE), "csv")
})

test_that("chunked TSV infers tabs and locks types without warnings", {
  skip_if_not_installed("yaml")
  # `note` carries a quoted tab (the delimiter) to exercise quoted-field
  # parsing. Records stay on one physical line: the CSV backend chunks by
  # line, so embedded newlines are out of scope (convert via dcc_read()).
  df <- data.frame(
    sid = c("S1", "S2", "S3", "S4"),
    score = c(101, NA, NA, 99),
    note = c("a\tb", "plain", NA, "ok")
  )
  path <- tempfile(fileext = ".tsv")
  data.table::fwrite(df, path, sep = "\t", quote = TRUE)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    max: 100"
  ), rules_file)
  rules <- dcc_rules(rules_file)

  expect_no_warning(got <- dcc_detect_chunked(path, rules, chunk_size = 2L,
                                               id_var = "sid"))
  expected <- dcc_detect(dcc_read(path), rules, id_var = "sid")
  expect_identical(normalize_findings(got), normalize_findings(expected))
  expect_identical(attr(got, "n_chunks", exact = TRUE), 2L)
})

test_that("chunked CSV at an exact chunk multiple emits no warnings", {
  skip_if_not_installed("yaml")
  df <- data.frame(
    sid = c("S1", "S2", "S3", "S4"),
    score = c(150, 20, NA, 99)
  )
  path <- tempfile(fileext = ".csv")
  data.table::fwrite(df, path)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    min: 0",
    "    max: 100"
  ), rules_file)
  rules <- dcc_rules(rules_file)

  # 4 rows / chunk_size 2 is an exact multiple: the reader must stop
  # cleanly at EOF rather than warn on a skip beyond the last row.
  expect_no_warning(got <- dcc_detect_chunked(path, rules, chunk_size = 2L,
                                               id_var = "sid"))
  expected <- dcc_detect(dcc_read(path), rules, id_var = "sid")
  expect_identical(normalize_findings(got), normalize_findings(expected))
  expect_identical(attr(got, "n_chunks", exact = TRUE), 2L)
})

test_that("chunked CSV reads latin1 input without warnings", {
  skip_if_not_installed("yaml")
  df <- data.frame(
    sid = c("S1", "S2", "S3", "S4"),
    city = c("café", "naïve", "Zürich", "plain"),
    score = c(101, 50, NA, 99)
  )
  path <- tempfile(fileext = ".csv")
  txt <- c(
    paste(names(df), collapse = ","),
    vapply(seq_len(nrow(df)), function(i) {
      paste(vapply(df[i, ], function(v) if (is.na(v)) "" else as.character(v),
                   character(1)), collapse = ",")
    }, character(1))
  )
  raw <- stringi::stri_conv(paste0(paste(txt, collapse = "\n"), "\n"),
                            from = "UTF-8", to = "latin1", to_raw = TRUE)[[1]]
  writeBin(raw, path)
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    max: 100"
  ), rules_file)
  rules <- dcc_rules(rules_file)

  expect_no_warning(got <- dcc_detect_chunked(path, rules, chunk_size = 3L,
                                               id_var = "sid",
                                               encoding = "latin1"))
  expected <- dcc_detect(dcc_read(path, encoding = "latin1"), rules,
                         id_var = "sid")
  expect_identical(normalize_findings(got), normalize_findings(expected))
})

test_that("arrow backend equals in-memory findings", {
  skip_if_not_installed("arrow")
  fx <- chunk_fixture()
  pq <- tempfile(fileext = ".parquet")
  arrow::write_parquet(data.table::fread(fx$csv), pq)
  in_mem <- dcc_detect(dcc_read(fx$csv), fx$rules, id_var = "sid")
  # auto-selection picks the arrow backend from the .parquet extension
  for (cs in c(3L, 5L, 4L, 100L)) {
    chunked <- dcc_detect_chunked(pq, fx$rules, chunk_size = cs,
                                  id_var = "sid")
    expect_identical(attr(chunked, "backend", exact = TRUE), "arrow")
    expect_identical(normalize_findings(chunked),
                     normalize_findings(in_mem),
                     label = paste("arrow chunk_size", cs))
  }
})

test_that("Arrow Parquet and Feather batches match in-memory findings", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("yaml")
  df <- data.frame(
    sid = sprintf("S%02d", 1:6),
    score = c(1, 101, NA, 3, 102, 5),
    integer_col = 1:6,
    double_col = as.numeric(1:6) / 2,
    character_col = c("a", "b", NA, "d", "e", "f"),
    logical_col = c(TRUE, FALSE, NA, TRUE, FALSE, TRUE),
    date_col = as.Date("2026-01-01") + 0:5,
    stringsAsFactors = FALSE
  )
  rules_file <- tempfile(fileext = ".yaml")
  writeLines(c(
    "checks:",
    "  - id: R001",
    "    type: range",
    "    variable: score",
    "    max: 100"
  ), rules_file)
  rules <- dcc_rules(rules_file)
  expected <- dcc_detect(df, rules, id_var = "sid")
  for (ext in c("parquet", "feather")) {
    path <- tempfile(fileext = paste0(".", ext))
    if (ext == "parquet") {
      arrow::write_parquet(df, path)
    } else {
      arrow::write_feather(df, path)
    }
    got <- dcc_detect_chunked(path, rules, chunk_size = 2L, id_var = "sid")
    expect_identical(normalize_findings(got), normalize_findings(expected),
                     label = paste("arrow", ext))
    expect_identical(attr(got, "n_chunks", exact = TRUE), 3L)
  }
})

test_that("arrow backend rejects a missing id_var with a typed error", {
  skip_if_not_installed("arrow")
  fx <- chunk_fixture()
  pq <- tempfile(fileext = ".parquet")
  arrow::write_parquet(data.table::fread(fx$csv), pq)
  expect_error(
    dcc_detect_chunked(pq, fx$rules, id_var = "nope"),
    class = "dcc_type_error"
  )
})

test_that("unknown extension needs an explicit backend", {
  fx <- chunk_fixture()
  odd <- tempfile(fileext = ".dat")
  file.copy(fx$csv, odd)
  expect_error(dcc_detect_chunked(odd, fx$rules),
               class = "dcc_type_error")
  # explicit override reads the same bytes as CSV
  forced <- dcc_detect_chunked(odd, fx$rules, id_var = "sid",
                               backend = "csv")
  expect_identical(attr(forced, "backend", exact = TRUE), "csv")
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
  rt <- f[f$check_id == "D003", ]
  expect_identical(rt$detector_id, "Q_RESPONSE_TIME")
  expect_identical(rt$record_id, "S003")
})
