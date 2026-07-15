test_that("every workflow help code has Chinese and English guidance", {
  zh <- dcc_help(language = "zh-CN")
  en <- dcc_help(language = "en")
  expect_setequal(zh$code, en$code)
  expect_setequal(zh$code, dcc_workflow_help_codes())
  expect_false(anyNA(zh$explanation))
  expect_false(anyNA(zh$fix))
  expect_true(all(nzchar(zh$explanation)))
  expect_true(all(nzchar(en$fix)))
  expect_identical(anyDuplicated(zh$code), 0L)
})

test_that("dcc_help looks up one stable code", {
  hit <- dcc_help("PLAN_COLUMN_TYPE")
  expect_identical(hit$code, "PLAN_COLUMN_TYPE")
  expect_match(hit$fix, "type|类型")
  expect_error(dcc_help("NO_SUCH_CODE"), class = "dcc_help_error")
  expect_error(dcc_help(language = "fr"), class = "dcc_help_error")
})
