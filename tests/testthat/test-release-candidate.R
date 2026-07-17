test_that("release candidate identity is frozen at DCC 1.2.0", {
  skip_without_dcc_source()
  description <- read.dcf(dcc_source_path("DESCRIPTION"))
  expect_identical(unname(description[1L, "Version"]), "1.2.0")

  news <- readLines(dcc_source_path("NEWS.md"), warn = FALSE)
  expect_identical(news[1L], "# DCC 1.2.0")
  expect_false(grepl("development", news[1L], ignore.case = TRUE))
})

test_that("local release evidence cannot leak into the source package", {
  skip_without_dcc_source()
  path <- dcc_source_path(".Rbuildignore")
  if (!file.exists(path)) {
    succeed("The installed package does not contain source build controls.")
    return(invisible(NULL))
  }
  ignore <- readLines(path, warn = FALSE)
  expect_true("^artifacts$" %in% ignore)
  expect_true("^DCC[.]Rcheck" %in% ignore)
  expect_true("^DCC_.*[.]tar[.]gz$" %in% ignore)
  expect_true(
    "^tests/acceptance/staff/.*[.]inspect[.]ndjson$" %in% ignore
  )
})
