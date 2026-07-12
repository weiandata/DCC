test_that("detect_missing_items flags high-missing respondents only", {
  df <- fixture_responses()
  f <- detect_missing_items(df, item_names(), max_prop = 0.5,
                            id_var = "sid")
  expect_identical(f$record_id, "S005")
  expect_identical(unique(f$check_id), "Q_MISSING_ITEMS")
  expect_identical(unique(f$dimension), "completeness")

  # lower threshold also catches S004 (40% missing exceeds 30%)
  f2 <- detect_missing_items(df, item_names(), max_prop = 0.3,
                             id_var = "sid")
  expect_setequal(f2$record_id, c("S004", "S005"))
})

test_that("detect_straightlining computes longstring correctly", {
  df <- fixture_responses()
  f <- detect_straightlining(df, item_names(), max_run = 10L,
                             id_var = "sid")
  expect_identical(f$record_id, "S003")

  f2 <- detect_straightlining(df, item_names(), max_run = 5L,
                              id_var = "sid")
  expect_setequal(f2$record_id, c("S003", "S008"))
  # S007's longest run is 3: not flagged even at max_run = 4
  f3 <- detect_straightlining(df, item_names(), max_run = 4L,
                              id_var = "sid")
  expect_false("S007" %in% f3$record_id)
})

test_that("detect_response_time applies absolute and relative cuts", {
  df <- fixture_responses()
  # absolute only: S003 (40s) below 60s
  f <- detect_response_time(df, "time_total", min_seconds = 60,
                            min_median_ratio = NULL, id_var = "sid")
  expect_identical(f$record_id, "S003")
  # relative: median ~ 595; S008 (200s) < 1/2 median; S003 caught too
  f2 <- detect_response_time(df, "time_total", min_seconds = NULL,
                             min_median_ratio = 0.5, id_var = "sid")
  expect_setequal(f2$record_id, c("S003", "S008"))
})

test_that("detect_trap_items respects expected values and NA policy", {
  df <- fixture_responses()
  f <- detect_trap_items(df, traps = list(trap1 = 3), id_var = "sid")
  expect_setequal(f$record_id, c("S003", "S007"))
  expect_identical(unique(f$severity), "fail")

  df$trap1[1] <- NA
  f2 <- detect_trap_items(df, traps = list(trap1 = 3), id_var = "sid")
  expect_true("S001" %in% f2$record_id)
  f3 <- detect_trap_items(df, traps = list(trap1 = 3), id_var = "sid",
                          na_fails = FALSE)
  expect_false("S001" %in% f3$record_id)
})

test_that("detect_score_anomaly finds within-group outliers", {
  df <- fixture_responses()
  # Group A scores: 80, 82, 15, 81 -> 15 is an IQR outlier
  f <- detect_score_anomaly(df, "score", group_vars = "grp",
                            id_var = "sid")
  expect_true("S003" %in% f$record_id[f$check_id == "Q_SCORE_OUTLIER"])
  expect_false("S005" %in% f$record_id)
})

test_that("detect_score_anomaly flags shifted group means", {
  df <- fixture_responses()
  df$score <- c(80, 82, 81, 79, 30, 31, 29, 32) # B far below overall
  f <- detect_score_anomaly(df, "score", group_vars = "grp",
                            id_var = "sid", group_mean_z = 0.9)
  shift <- f[f$check_id == "Q_GROUP_SCORE_SHIFT", ]
  expect_gte(nrow(shift), 1L)
  expect_true(all(is.na(shift$record_id)))
  expect_true(any(grepl("grp=B", shift$evidence)))
})

test_that("detectors error informatively on bad input", {
  df <- fixture_responses()
  expect_error(detect_missing_items(df, c("q1", "nope")),
               class = "dcc_type_error")
  expect_error(detect_response_time(df, "nope"),
               class = "dcc_type_error")
  expect_error(detect_trap_items(df, traps = list(3)),
               class = "dcc_type_error")
  expect_error(detect_score_anomaly(df, "nope"),
               class = "dcc_type_error")
})

test_that("zero-hit detectors return zero findings", {
  df <- fixture_responses()
  f <- detect_missing_items(df, item_names(), max_prop = 0.99,
                            id_var = "sid")
  expect_identical(nrow(f), 0L)
  f2 <- detect_trap_items(df[df$sid == "S001", ],
                          traps = list(trap1 = 3), id_var = "sid")
  expect_identical(nrow(f2), 0L)
})

test_that("detectors accept dcc_data objects", {
  x <- dcc_data(fixture_responses())
  f <- detect_straightlining(x, item_names(), max_run = 10L,
                             id_var = "sid")
  expect_identical(f$record_id, "S003")
})
