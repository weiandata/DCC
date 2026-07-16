dependency_tool <- testthat::test_path(
  "..", "..", "tools", "verify-dependencies.R"
)

test_that("every format backend installs with DCC", {
  description <- read.dcf(testthat::test_path("..", "..", "DESCRIPTION"))
  imports <- trimws(strsplit(description[1L, "Imports"], ",")[[1L]])
  imports <- sub("[[:space:]]*\\(.*$", "", imports)
  required <- c(
    "arrow", "data.table", "haven", "jsonlite", "openxlsx2", "readODS",
    "readxl", "stringi", "writexl", "yaml"
  )

  expect_setequal(intersect(imports, required), required)
  expect_match(description[1L, "Config/DCC/Installation"], "complete")
})

test_that("dependency audit rejects undeclared calls and runtime installers", {
  expect_true(file.exists(dependency_tool))
  source(dependency_tool, local = TRUE)
  root <- testthat::test_path("..", "..")
  audit <- audit_dependencies(root)

  expect_true(audit$ok)
  expect_length(audit$undeclared_namespace_calls, 0L)
  expect_length(audit$runtime_install_calls, 0L)
  expect_setequal(audit$format_dependencies, format_dependencies())
})

test_that("dependency lock covers the installed recursive closure", {
  source(dependency_tool, local = TRUE)
  root <- testthat::test_path("..", "..")
  lock <- jsonlite::read_json(file.path(root, "renv.lock"), simplifyVector = FALSE)
  audit <- audit_dependencies(root)

  expect_identical(lock$R$Version, paste(R.version$major, R.version$minor, sep = "."))
  expect_true(all(audit$locked_packages %in% names(lock$Packages)))
  expect_length(audit$lock_version_mismatches, 0L)
})

test_that("internal bundle contract is complete or fails closed", {
  builder <- testthat::test_path(
    "..", "..", "tools", "build-internal-bundle.R"
  )
  expect_true(file.exists(builder))
  text <- paste(readLines(builder, warn = FALSE), collapse = "\n")

  expect_match(text, "write_PACKAGES", fixed = TRUE)
  expect_match(text, "SHA256SUMS", fixed = TRUE)
  expect_match(text, "license-inventory", fixed = TRUE)
  expect_match(text, "INTERNAL BUNDLE: INCOMPLETE", fixed = TRUE)
  expect_false(grepl("user data", text, fixed = TRUE) &&
                 grepl("file.copy(user", text, fixed = TRUE))
})

test_that("internal bundle checksums use relocatable relative paths", {
  builder <- testthat::test_path(
    "..", "..", "tools", "build-internal-bundle.R"
  )
  source(builder, local = TRUE)
  root <- withr::local_tempdir()
  dir.create(file.path(root, "repository"))
  writeLines("fixture", file.path(root, "repository", "file.txt"))

  write_checksums(root)
  line <- readLines(file.path(root, "SHA256SUMS"))
  expect_match(line, " repository/file.txt$", perl = TRUE)
  expect_false(grepl(basename(root), line, fixed = TRUE))
})
