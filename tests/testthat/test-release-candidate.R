test_that("release candidate identity is frozen at DCC 1.2.0", {
  description <- read.dcf(dcc_source_path("DESCRIPTION"))
  expect_identical(unname(description[1L, "Version"]), "1.2.0")

  news <- readLines(dcc_source_path("NEWS.md"), warn = FALSE)
  expect_identical(news[1L], "# DCC 1.2.0")
  expect_false(grepl("development", news[1L], ignore.case = TRUE))
})
