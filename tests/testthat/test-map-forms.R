forms_df <- function() {
  data.frame(
    sid = c("S1", "S2", "S3", "S4"),
    form = c("A", "A", "B", "B"),
    p1 = c(1, 2, 3, 4),   # form A: item M001 / form B: item M003
    p2 = c(5, 6, 7, 8),   # form A: item M002 / form B: item M002 (anchor)
    stringsAsFactors = FALSE
  )
}

forms_map <- function() {
  data.frame(
    form = c("A", "A", "B", "B"),
    source = c("p1", "p2", "p1", "p2"),
    master = c("M001", "M002", "M003", "M002"),
    is_anchor = c(FALSE, TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}

test_that("forms map onto the master bank with structural NA", {
  out <- dcc_map_forms(forms_df(), forms_map(), form_var = "form")
  df <- as.data.frame(out)
  # master columns exist; source columns consumed
  expect_true(all(c("M001", "M002", "M003") %in% names(df)))
  expect_false(any(c("p1", "p2") %in% names(df)))
  # form A respondents have M001, not M003 (not administered)
  expect_identical(df$M001, c("1", "2", NA, NA))
  expect_identical(df$M003, c(NA, NA, "3", "4"))
  # anchor item M002 filled for everyone
  expect_identical(df$M002, c("5", "6", "7", "8"))
})

test_that("anchor flags are carried in the attached item map", {
  out <- dcc_map_forms(forms_df(), forms_map(), form_var = "form")
  imap <- attr(out, "dcc_item_map", exact = TRUE)
  expect_true(all(imap$is_anchor[imap$master == "M002"]))
  expect_false(any(imap$is_anchor[imap$master == "M001"]))
})

test_that("missing source columns become findings, not silent drops", {
  m <- forms_map()
  m$source[1] <- "p9" # not in data
  out <- dcc_map_forms(forms_df(), m, form_var = "form")
  f <- attr(out, "dcc_findings", exact = TRUE)
  expect_true("MAP_SOURCE_MISSING" %in% f$check_id)
  # the rest of the mapping still happened
  expect_true("M002" %in% names(as.data.frame(out)))
})

test_that("unknown forms become findings and stay NA", {
  df <- forms_df()
  df$form[4] <- "C"
  out <- dcc_map_forms(df, forms_map(), form_var = "form")
  f <- attr(out, "dcc_findings", exact = TRUE)
  expect_true("MAP_UNKNOWN_FORM" %in% f$check_id)
  d <- as.data.frame(out)
  expect_true(all(is.na(d[4, c("M001", "M002", "M003")])))
})

test_that("map validation is typed", {
  expect_error(dcc_map_forms(forms_df(), forms_map(), form_var = "nope"),
               class = "dcc_type_error")
  expect_error(dcc_map_forms(forms_df(), data.frame(a = 1), "form"),
               class = "dcc_map_error")
  dup <- rbind(forms_map(), forms_map()[1, ])
  expect_error(dcc_map_forms(forms_df(), dup, "form"),
               class = "dcc_map_error")
  incons <- forms_map()
  incons$is_anchor[4] <- FALSE # M002 anchor on A but not B
  expect_error(dcc_map_forms(forms_df(), incons, "form"),
               class = "dcc_map_error")
  expect_error(dcc_map_forms(forms_df(), "no-such.csv", "form"),
               class = "dcc_io_error")
})

test_that("map from CSV records hash in provenance", {
  f <- tempfile(fileext = ".csv")
  data.table::fwrite(forms_map(), f)
  out <- dcc_map_forms(dcc_data(forms_df()), f, form_var = "form")
  prov <- dcc_provenance(out)
  det <- prov$details[[which(prov$stage == "map_forms")]]
  expect_identical(det$map_hash, unname(tools::md5sum(f)))
  expect_identical(det$n_anchors, 1L)
  expect_identical(det$n_masters, 3L)
})

test_that("end-to-end: map then score with na omit policy", {
  df <- forms_df()
  # responses become letters for scoring
  df$p1 <- c("A", "B", "C", "C")
  df$p2 <- c("D", "D", "D", "E")
  mapped <- dcc_map_forms(df, forms_map(), form_var = "form")
  key <- data.frame(item = c("M001", "M002", "M003"),
                    key = c("A", "D", "C"))
  scored <- as.data.frame(dcc_score(mapped, key, omit_policy = "na"))
  # not-administered items remain NA-scored, answered ones scored
  expect_identical(scored$M001_score, c(1, 0, NA, NA))
  expect_identical(scored$M002_score, c(1, 1, 1, 0))
  expect_identical(scored$M003_score, c(NA, NA, 1, 1))
  expect_identical(scored$total_score, c(2, 1, 2, 1))
})
