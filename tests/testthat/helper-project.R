dcc_source_root <- function() {
  configured <- Sys.getenv("DCC_SOURCE_ROOT", "")
  test_root <- testthat::test_path("..", "..")
  candidates <- unique(c(
    if (nzchar(configured)) configured else character(),
    file.path(test_root, "00_pkg_src", "DCC"),
    test_root,
    file.path(test_root, "DCC")
  ))
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "DESCRIPTION")) &&
        dir.exists(file.path(candidate, "tools"))) {
      return(normalizePath(candidate, mustWork = TRUE))
    }
  }
  stop("Cannot locate the DCC source root from the test environment.")
}

dcc_source_path <- function(...) file.path(dcc_source_root(), ...)
