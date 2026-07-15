statistical_fixture <- function(format) {
  path <- tempfile(fileext = paste0(".", format))
  data <- data.frame(
    sid = c("001", "002"),
    q1 = haven::labelled(c(1, haven::tagged_na("a")),
                         labels = c(Yes = 1), label = "Question 1")
  )
  if (format == "sav") {
    data$q1 <- haven::labelled_spss(
      c(1, 9), labels = c(Yes = 1, Missing = 9),
      na_values = 9, label = "Question 1"
    )
    haven::write_sav(data, path)
  } else if (format == "dta") {
    haven::write_dta(data, path)
  } else if (format == "sas7bdat") {
    suppressWarnings(haven::write_sas(
      data.frame(sid = c("001", "002"), q1 = c(1, 2)), path
    ))
  } else if (format == "xpt") {
    haven::write_xpt(data.frame(sid = c("001", "002"), q1 = c(1, 2)), path)
  } else {
    stop("unknown statistical fixture")
  }
  path
}

test_that("statistical adapters retain labels and declared missings", {
  path <- statistical_fixture("sav")
  raw <- dcc_get_adapter("spss")$reader(path, list())
  expect_identical(raw$metadata$variables$q1$label, "Question 1")
  expect_identical(unname(raw$metadata$variables$q1$labels["Yes"]), 1)
  expect_true("declared_missing_code" %in% raw$metadata$missing$state)
  expect_identical(raw$data$sid, c("001", "002"))
})

test_that("Stata tagged missing metadata is retained before conversion", {
  path <- statistical_fixture("dta")
  raw <- dcc_get_adapter("stata")$reader(path, list())
  expect_identical(raw$metadata$variables$q1$label, "Question 1")
  expect_true(any(raw$metadata$missing$source_value == "NA(a)"))
  expect_true(any(raw$metadata$missing$state == "declared_missing_code"))
})

test_that("haven dispatch covers SAS and XPT tables", {
  sas <- dcc_get_adapter("sas")$reader(
    statistical_fixture("sas7bdat"), list()
  )
  xpt <- dcc_get_adapter("xpt")$reader(
    statistical_fixture("xpt"), list()
  )
  expect_identical(sas$data$sid, c("001", "002"))
  expect_identical(xpt$data$sid, c("001", "002"))
})

test_that("canonical statistical import keeps source labels and missing state", {
  path <- statistical_fixture("sav")
  columns <- data.frame(
    source_name = c("sid", "q1"), name = c("sid", "q1"),
    type = c("character", "integer"), role = c("id", "item"),
    stringsAsFactors = FALSE
  )
  spec <- new_import_spec(path, "spss", columns = columns)
  x <- dcc_import(path, spec)
  expect_identical(x$data$q1, c(1L, NA_integer_))
  expect_identical(dcc_dictionary(x)$label[2L], "Question 1")
  expect_identical(dcc_missing_states(x)$state,
                   "declared_missing_code")
})
