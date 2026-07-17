# Locate the DCC source tree (DESCRIPTION + tools/) from the test environment.
# Release-infrastructure tests exercise scripts under tools/ and files such as
# renv.lock that ship in the tarball but are not installed into the package
# library. During `R CMD check` on a clean machine (CRAN, win-builder) the
# unpacked source is not reliably reachable from the test working directory, so
# these lookups must fail soft: the tests skip instead of erroring. When the
# source IS reachable (developer checkout, `test_local()`, coverage runs, and
# the nested CI check layout) they run normally, keeping the zero-skip release
# gate satisfied.

dcc_source_root_or_null <- function() {
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
  NULL
}

dcc_source_available <- function() !is.null(dcc_source_root_or_null())

# Skip the calling test when the source tree is unavailable. Use as the first
# line of any test that reads tools/, renv.lock, or other source-only files.
skip_without_dcc_source <- function() {
  testthat::skip_if_not(
    dcc_source_available(),
    "requires the DCC source tree (skipped in installed-package checks)"
  )
}

dcc_source_root <- function() {
  root <- dcc_source_root_or_null()
  if (is.null(root)) {
    testthat::skip("DCC source tree is unavailable (installed-package check).")
  }
  root
}

# Top-level safe: when the source is unavailable this returns a non-existent
# placeholder rather than erroring, so test files that capture a tool path at
# load time still parse. The test bodies gate on skip_without_dcc_source().
dcc_source_path <- function(...) {
  root <- dcc_source_root_or_null()
  if (is.null(root)) {
    return(file.path(tempfile("dcc-source-unavailable-"), ...))
  }
  file.path(root, ...)
}
