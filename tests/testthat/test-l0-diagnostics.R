test_that("clean table produces no findings", {
  rep <- dcc_l0_diagnose(fixture_df())
  expect_identical(nrow(rep$findings), 0L)
  expect_identical(rep$n_rows, 3L)
  expect_identical(rep$n_cols, 5L)
  expect_identical(rep$columns$n_missing[rep$columns$name == "q1"], 1L)
})

test_that("empty table is a fail finding", {
  rep <- dcc_l0_diagnose(data.frame(a = character(), b = integer()))
  expect_true("L0_EMPTY_TABLE" %in% rep$findings$check_id)
  expect_identical(
    rep$findings[rep$findings$check_id == "L0_EMPTY_TABLE", ]$severity,
    "fail"
  )
})

test_that("duplicate and placeholder column names are flagged", {
  df <- data.frame(a = 1:2, b = 3:4)
  names(df) <- c("x", "x")
  rep <- dcc_l0_diagnose(df)
  expect_true("L0_DUPLICATE_COLNAME" %in% rep$findings$check_id)

  df2 <- data.frame(1:2, 3:4) # names become V1-style placeholders
  names(df2) <- c("V1", "V2")
  rep2 <- dcc_l0_diagnose(df2)
  expect_true("L0_UNNAMED_COLUMN" %in% rep2$findings$check_id)
})

test_that("all-missing columns and empty rows are flagged", {
  df <- data.frame(a = c(1, NA), b = c(NA_real_, NA_real_))
  rep <- dcc_l0_diagnose(df)
  expect_true("L0_ALL_MISSING_COLUMN" %in% rep$findings$check_id)
  expect_true("L0_EMPTY_ROWS" %in% rep$findings$check_id)
})

test_that("single-column parse warns (likely delimiter problem)", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("a;b;c", "1;2;3"), f, useBytes = TRUE)
  x <- dcc_read(f) # comma expected, semicolons present -> fread may parse 1 col
  rep <- dcc_read_report(x)
  if (rep$n_cols == 1L) {
    expect_true("L0_SINGLE_COLUMN" %in% rep$findings$check_id)
  } else {
    succeed() # fread auto-sniffed the delimiter; also acceptable
  }
})

test_that("low encoding confidence is surfaced", {
  rep <- dcc_l0_diagnose(
    fixture_df(),
    meta = list(encoding = "GB18030", encoding_confidence = 0.42)
  )
  expect_true("L0_ENCODING_UNCERTAIN" %in% rep$findings$check_id)
})
