#!/usr/bin/env Rscript

# Pin the installed library to the exact renv.lock closure.
#
# CI installs dependencies with the r-lib setup action, which resolves the
# latest CRAN versions. This step then reinstalls every package recorded in
# renv.lock at its locked version, so the build validates the same dependency
# closure the offline bundle ships and the dependency-contract invariant
# (locked == installed direct-import versions) holds regardless of CRAN drift.
#
# When the lock is current every locked version already equals the installed
# version, so pak is a no-op and the step is fast. During a drift window (a
# direct import published a newer CRAN version than the lock records) pak
# reinstalls just that package at the locked version, keeping CI green until
# the lock is deliberately re-frozen. Suggests and check tooling (testthat,
# rcmdcheck, covr, ...) are not in the lock and are left at their installed
# versions; the contract audit does not pin them.

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite must be installed before pinning the locked closure.")
}
if (!requireNamespace("pak", quietly = TRUE)) {
  stop("pak must be installed before pinning the locked closure.")
}

args <- commandArgs(trailingOnly = TRUE)
lock_path <- if (length(args) >= 1L && nzchar(args[[1L]])) args[[1L]] else "renv.lock"
if (!file.exists(lock_path)) {
  stop("Lock file not found: ", lock_path)
}

lock <- jsonlite::read_json(lock_path, simplifyVector = FALSE)
packages <- lock$Packages
if (!length(packages)) {
  stop("Lock file records no packages: ", lock_path)
}

specs <- vapply(packages, function(record) {
  package <- record$Package
  version <- record$Version
  if (is.null(package) || is.null(version) ||
      !nzchar(package) || !nzchar(version)) {
    stop("Lock file has a package without a name or version.")
  }
  paste0(package, "@", version)
}, character(1L))
specs <- unname(specs)

installed <- rownames(utils::installed.packages())
current <- vapply(packages, function(record) {
  if (record$Package %in% installed &&
      identical(as.character(utils::packageVersion(record$Package)),
                as.character(record$Version))) {
    "match"
  } else {
    "reinstall"
  }
}, character(1L))
drifted <- specs[current == "reinstall"]

cat(sprintf("Pinning %d locked package(s); %d already match, %d to (re)install.\n",
            length(specs), sum(current == "match"), length(drifted)))
if (length(drifted)) {
  cat("  ", paste(drifted, collapse = "\n   "), "\n", sep = "")
}

if (identical(Sys.getenv("CI_INSTALL_DRYRUN"), "1")) {
  cat("CI_INSTALL_DRYRUN=1 set; not installing.\n")
  quit(status = 0L)
}

pak::pkg_install(specs, ask = FALSE, upgrade = FALSE)
cat("Locked closure installed.\n")
