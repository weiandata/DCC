score_df <- function() {
  data.frame(
    sid = c("S1", "S2", "S3"),
    it1 = c("A", "B", NA),          # key A
    it2 = c("AC", "A", "ABC"),      # key AC, multiple
    stringsAsFactors = FALSE
  )
}

score_key <- function() {
  data.frame(
    item = c("it1", "it2"),
    key = c("A", "AC"),
    type = c("single", "multiple"),
    points = c(1, 2),
    partial = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
}

test_that("single and multiple all-or-nothing scoring works", {
  out <- dcc_score(score_df(), score_key())
  df <- as.data.frame(out)
  expect_identical(df$it1_score, c(1, 0, 0))   # NA -> 0 under zero policy
  expect_identical(df$it2_score, c(2, 0, 0))   # exact match only
  expect_identical(df$total_score, c(3, 0, 0))
})

test_that("partial credit rewards hits and penalizes false alarms", {
  key <- score_key()
  key$partial[2] <- TRUE
  out <- dcc_score(score_df(), key)
  df <- as.data.frame(out)
  # S2 chose A of key {A,C}: (1-0)/2 * 2 points = 1
  expect_identical(df$it2_score[2], 1)
  # S3 chose ABC: hits 2, false alarm 1 -> (2-1)/2 * 2 = 1
  expect_identical(df$it2_score[3], 1)
})

test_that("omit policy na keeps omitted items NA", {
  out <- dcc_score(score_df(), score_key(), omit_policy = "na")
  df <- as.data.frame(out)
  expect_true(is.na(df$it1_score[3]))
  # total uses na.rm: S3 still gets its it2 score counted
  expect_identical(df$total_score[3], 0)
})

test_that("pluggable scoring_fn overrides built-ins", {
  half <- function(resp, krow) rep(0.5, length(resp))
  out <- dcc_score(score_df(), score_key(), scoring_fn = half)
  df <- as.data.frame(out)
  expect_identical(unique(df$it1_score), 0.5)
})

test_that("answer key from CSV records hash in provenance", {
  f <- tempfile(fileext = ".csv")
  data.table::fwrite(score_key(), f)
  x <- dcc_data(score_df())
  out <- dcc_score(x, f)
  prov <- dcc_provenance(out)
  det <- prov$details[[which(prov$stage == "score")]]
  expect_identical(det$keyfile_hash, unname(tools::md5sum(f)))
  expect_identical(det$n_items, 2L)
})

test_that("answer key validation is typed", {
  expect_error(dcc_score(score_df(), data.frame(a = 1)),
               class = "dcc_score_error")
  bad_type <- score_key()
  bad_type$type[1] <- "essay"
  expect_error(dcc_score(score_df(), bad_type),
               class = "dcc_score_error")
  dup <- rbind(score_key(), score_key()[1, ])
  expect_error(dcc_score(score_df(), dup), class = "dcc_score_error")
  missing_item <- score_key()
  missing_item$item[1] <- "nope"
  expect_error(dcc_score(score_df(), missing_item),
               class = "dcc_score_error")
  expect_error(dcc_score(score_df(), "no-such-file.csv"),
               class = "dcc_io_error")
})

test_that("multi-select separators are tolerated", {
  df <- score_df()
  df$it2 <- c("A,C", "a", "A C")
  key <- score_key()
  out <- dcc_score(df, key)
  d <- as.data.frame(out)
  expect_identical(d$it2_score[1], 2) # "A,C" == {A,C}
  expect_identical(d$it2_score[2], 0) # case-sensitive: "a" != "A"
  expect_identical(d$it2_score[3], 2) # "A C" == {A,C}
})

test_that("NA responses on multiple-select items follow omit policy", {
  df <- score_df()
  df$it2[2] <- NA
  out <- as.data.frame(dcc_score(df, score_key()))
  expect_identical(out$it2_score[2], 0) # zero policy
  out_na <- as.data.frame(dcc_score(df, score_key(), omit_policy = "na"))
  expect_true(is.na(out_na$it2_score[2]))
})
