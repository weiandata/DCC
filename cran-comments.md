# CRAN submission comments

Resubmission of DCC 1.2.1 at Uwe Ligges' request, after the earlier submission
was lost during review. The sources are unchanged apart from the `tools/`
documentation described below.

## Regarding the code in `tools/`

### When is it executed?

Never at install time. The package has no `configure`, `configure.win`,
`cleanup`, `Makefile`, or `src/`, and no `.onLoad`/`.onAttach` hook. Nothing in
`R/` refers to `tools/`, and `R CMD INSTALL` does not copy the directory into
the library, so it does not exist in an installed DCC.

These are maintainer and CI release scripts. They run only when I invoke them
from a source checkout, or from our GitHub Actions workflows. During
`R CMD check` a few tests `source()` some of them to unit-test their pure
helper functions; every script keeps its work inside `main()` behind
`if (sys.nframe() == 0L) main()`, so sourcing only defines functions. One test
additionally runs `Rscript tools/verify-format-matrix.R --local` in a
subprocess, which is read-only and writes no file.

### Are packages installed?

Not by building, installing, checking, or using DCC. All input backends are
ordinary `Imports`. One script, `tools/ci-install-locked.R`, installs packages
via `pak::pkg_install()` to pin our CI runner's library to `renv.lock`; it is
only ever a GitHub Actions step and is not referenced from `R/`, `tests/`,
`man/`, or `vignettes/`.

Please note that `tools/build-internal-bundle.R` installs nothing: the
`install.packages(...)` text in it is a string literal that it writes into an
offline bundle for internal users to run themselves.

### Are files written to the user or library file space?

No. Nothing writes to `.libPaths()` or to the user's home directory. No
exported function has a default write path, and all examples, tests, and
vignettes write only under `tempdir()`. When I run a `tools/` script
deliberately, its output stays inside the source checkout.

`tools/README.md` is included in the tarball and documents this per script,
with a table stating for each one whether it runs during check, whether it
installs packages, and where it writes.

## Check results

`R CMD check --as-cran`: 0 errors, 0 warnings.

The words flagged as possibly misspelled in `DESCRIPTION` are intentional:
"WeianData" is the copyright holder's company name, "JSONL" is the
newline-delimited JSON format, "dcc" is the first token of the exported class
`dcc_data`, and "backends" and "preflight" are standard technical terms.

## Test environments

* Ubuntu, R devel and R release; macOS, R release; Windows, R release (CI)
* win-builder, R devel and R release: the only NOTE was the incoming
  feasibility NOTE (new submission plus the spellings above)
