codebook_spec <- function() {
  list(
    age = list(missing = -99, type = "integer"),
    sex = list(rename = "gender", recode = c("1" = "M", "2" = "F"),
               label = "Gender")
  )
}

test_that("dcc_apply_codebook previews without mutating the input", {
  df <- data.frame(sid = c("S1", "S2"), age = c(25, -99),
                   sex = c("1", "2"), stringsAsFactors = FALSE)
  prev <- dcc_apply_codebook(df, codebook_spec())
  expect_s3_class(prev, "dcc_codebook_preview")
  expect_true(nrow(dcc_codebook_changes(prev)) >= 4L)
  # the input data.frame is untouched
  expect_identical(df$age, c(25, -99))
  expect_true("sex" %in% names(df))
})

test_that("dcc_apply_codebook applies the previewed changes", {
  df <- data.frame(sid = c("S1", "S2"), age = c(25, -99),
                   sex = c("1", "2"), stringsAsFactors = FALSE)
  applied <- dcc_apply_codebook(df, codebook_spec(), dry_run = FALSE)
  ad <- as.data.frame(applied)
  expect_true(is.na(ad$age[2]))            # -99 declared missing
  expect_identical(ad$age[1], 25L)         # coerced to integer
  expect_true("gender" %in% names(ad))     # renamed
  expect_false("sex" %in% names(ad))
  # recoded (the column also carries the intended `label` attribute)
  expect_equal(ad$gender, c("M", "F"), ignore_attr = TRUE)
  expect_true("codebook" %in% dcc_provenance(applied)$stage)
})

test_that("an unknown codebook variable is a typed error", {
  df <- data.frame(sid = "S1", age = 25)
  expect_error(dcc_apply_codebook(df, list(nope = list(label = "x"))),
               class = "dcc_codebook_error")
})
