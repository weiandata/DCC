# CRAN submission comments

## Resubmission (2026-09-02)

This is a resubmission of DCC 1.2.1 at the request of Uwe Ligges, after the
earlier submission was lost during the review process. The sources are the
same package that was reviewed, with one addition described below: the
`tools/` directory now carries a `README.md` answering the questions in that
mail, and its scripts were made inert on `source()`.

### What the `tools/` directory is, and when its code runs

`tools/` holds the maintainer and continuous-integration scripts for the
release process (benchmark capture, coverage and dependency audits, acceptance
evidence, release-evidence assembly and validation). It is source-only. There
are exactly three ways any of it executes:

1. **In the test suite, during `R CMD check`.** Several tests under
   `tests/testthat/` `source(..., local = TRUE)` a script from `tools/` in
   order to unit-test its pure helper functions — contract parsers, evidence
   validators, comparators. Every script keeps all of its work inside `main()`
   behind `if (sys.nframe() == 0L) main()`, so sourcing defines functions and
   nothing else; `tools/agent-acceptance.R` is a function library with no
   top-level code at all. One test additionally runs
   `Rscript tools/verify-format-matrix.R --local` in a subprocess: with no
   `--output` argument it only reads the format fixtures and prints a result.
   All of these tests skip cleanly when the unpacked source tree is not
   reachable from the test directory.
2. **When the maintainer runs a script by hand from a source checkout.**
3. **From the GitHub Actions workflows in `.github/workflows/`.**

### Is anything executed at install time?

No. The package has no `configure`, `configure.win`, `cleanup`, `Makefile`, or
`src/`, and no `.onLoad`/`.onAttach` hook. Nothing under `R/` refers to
`tools/`. `R CMD INSTALL` does not copy `tools/` into the package library, so
the directory does not exist in an installed DCC.

### Are packages installed?

Not by installing, checking, or using DCC. Every declared backend is an
ordinary `Imports` and installs with the package; nothing is installed at
runtime, and `tools/verify-dependencies.R` is a gate that fails the build if
any file under `R/` gains an installer call or an undeclared namespace.

Two files mention installation, so to be explicit:

* `tools/ci-install-locked.R` is the only script that installs anything. It
  calls `pak::pkg_install()` to reinstall the packages recorded in `renv.lock`
  at their locked versions, so CI validates a fixed dependency closure. It is
  invoked only as a GitHub Actions step and acts on that runner's own library.
  It is not referenced by `R/`, `tests/`, `man/`, or `vignettes/`, is never
  reached by building, installing, or checking the package, and does nothing
  on `source()`.
* `tools/build-internal-bundle.R` installs nothing. It *writes out* a text
  file (`install-DCC.R`) into an offline bundle directory, so that an internal
  user without network access can later run it themselves against a library
  path they choose. The `install.packages(...)` text a scan finds in that
  script is the generated file's content, inside a string literal — not a call
  the package makes.

### Are files written to the user or library file space?

No. Nothing writes to `.libPaths()`, to the user's home directory, or to any
location outside what the caller names.

* Package functions write only where the caller asks. No exported function has
  a default write path: `dcc_check()`, `dcc_run()`, and `dcc_template()` take
  the destination as a required argument and error, pointing at `tempdir()`,
  if it is missing. `dcc_report()`, `dcc_export_log()`, `dcc_manifest()`,
  `dcc_report_staff()`, `dcc_report_statistical()`, `dcc_report_machine()`,
  and `dcc_write_config_template()` have always required an explicit path.
* All examples, tests, and vignettes write only under `tempdir()`.
* During `R CMD check` the `tools/` code writes nothing at all, as described
  above.
* When a maintainer runs one of these scripts deliberately, its output goes
  inside the source checkout — `artifacts/`, or for the three generator
  scripts the tracked files they regenerate. `artifacts/`, `examples/`,
  `docs/`, and `renv.lock` are in `.Rbuildignore` and are not in the tarball.

`tools/README.md` documents this per script, including a table stating for each
one whether it runs during check, whether it installs packages, and where it
writes.

## Earlier review points (1.2.0), still addressed

* `DESCRIPTION` no longer single-quotes file-format and markup names (CSV,
  Parquet, JSON, JSONL, YAML, HTML, PDF) or the package's own `dcc_data`
  container. Only third-party software names ('Excel', 'SPSS', 'Stata',
  'SAS') remain quoted.
* No exported function has a default write path any more (see above).
* All examples, tests, and vignettes write only under `tempdir()`; the
  remaining vignette chunk that showed a relative output directory now uses
  `file.path(tempdir(), "dcc-run")`.

## Test environments

The release workflow is configured for:

* Ubuntu, R devel
* Ubuntu, R release
* macOS, R release
* Windows, R release

Every release-candidate check uses `--as-cran` and requires zero actionable
NOTEs. Errors, warnings, test failures, test warnings, and test skips must also
all be zero.
The only allowed NOTE code is `cran_new_submission`, used solely for CRAN's
first-submission incoming classification. Any additional text in that NOTE,
any other NOTE, or any count mismatch remains blocking.

`DCC_1.2.1.tar.gz` was additionally checked on win-builder:

* Windows, R Under development (unstable) (2026-07-28 r90311 ucrt): Status 1 NOTE
* Windows, R 4.6.1 (2026-06-24 ucrt): Status 1 NOTE

In both runs the only NOTE is the incoming-feasibility NOTE: new submission
plus the possibly-misspelled words discussed under "Spelling". There were no
errors and no warnings.

## Spelling

The incoming feasibility check flags five words in `DESCRIPTION` as possibly
misspelled. All five are intentional and spelled correctly:

* "WeianData" is the copyright holder's company name.
* "backends" and "preflight" are standard technical terms used as written.
* "JSONL" is the newline-delimited JSON format written by the machine report.
* "dcc" is the first token of `dcc_data`, the exported S3 container class the
  package's readers return.

"JSONL" and "dcc" are newly flagged in 1.2.1 only because the review of 1.2.0
asked for the single quotes around format names to be removed; the words
themselves are unchanged.
