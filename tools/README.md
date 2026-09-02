# `tools/` — maintainer and CI scripts

## Summary for reviewers

* **Nothing in this directory runs when a user installs DCC.** The package has
  no `configure`, `configure.win`, `cleanup`, or `src/`, no `Makefile`, and no
  `.onLoad`/`.onAttach` hook. Nothing under `R/` refers to `tools/`. The
  directory is source-only: `R CMD INSTALL` does not copy it into the package
  library, so it does not exist in an installed DCC.
* **No script installs packages during installation, `R CMD check`, examples,
  vignettes, or normal use.** Exactly one script installs anything at all
  (`ci-install-locked.R`), it is a GitHub Actions step, and it is never reached
  by building, installing, or checking the package.
* **Nothing is ever written to the user's home directory or to any R library.**
  Package code writes only where the caller asks it to; the test suite,
  examples, and vignettes write only under `tempdir()`. When a maintainer runs a
  script here by hand, it writes inside the source checkout (`artifacts/`, and
  for the three generators the tracked files they regenerate) — never outside it.
* **Sourcing any file here has no side effects.** Every script keeps its work in
  `main()` behind `if (sys.nframe() == 0L) main()`, so `source()` only defines
  functions; `agent-acceptance.R` is a function library with no top-level code
  at all.

## When this code is executed

There are exactly three ways:

1. **During `R CMD check`, in the test suite.** Several release-infrastructure
   tests under `tests/testthat/` `source(..., local = TRUE)` scripts from this
   directory in order to unit-test their pure helper functions (contract
   parsers, evidence validators, comparators). Because of the `sys.nframe()`
   guard this only defines functions — no `main()` runs, nothing is installed,
   nothing is written. One test additionally runs
   `Rscript tools/verify-format-matrix.R --local` in a subprocess; with no
   `--output` argument that run is read-only and writes no file.

   All of these tests call `skip_without_dcc_source()` first
   (`tests/testthat/helper-project.R`), so they skip cleanly wherever the
   unpacked source tree is not reachable from the test directory.

2. **By the maintainer, deliberately, from a source checkout** (`Rscript
   tools/<script>.R ...`), when preparing a release.

3. **By GitHub Actions**, from the workflows in `.github/workflows/`.

DCC's own runtime never calls anything here. `tools/verify-dependencies.R`
exists precisely to enforce that: it fails if any file under `R/` contains an
installer call (`install.packages`, `pak::pkg_install`, `install_github`, …) or
uses an undeclared namespace.

## What each script does

Column meanings — *Installs pkgs*: does running it install R packages?
*Writes*: where a deliberate `Rscript` run puts output.

| Script | Purpose | Runs during check? | Installs pkgs | Writes |
| --- | --- | --- | --- | --- |
| `agent-acceptance.R` | Function library: agent acceptance-task contract and scoring. No top-level code. | sourced only | no | nothing (callers pass a path) |
| `benchmarks/benchmark.R` | Capture stage timings/memory on synthetic data. | no | no | `artifacts/benchmark-current.json` |
| `benchmarks/memory.R` | Check captured memory evidence against budgets. | sourced only | no | `artifacts/memory-current.json` |
| `build-example.R` | Regenerate `examples/strict-excel-project`. Maintainer only; needs devtools. | no | no | `examples/` in the checkout |
| `build-internal-bundle.R` | Assemble the offline install bundle for internal users. | sourced only | no | `artifacts/` in the checkout |
| `build-release-evidence.R` | Collect CI gate outputs into one release-evidence document. | sourced only | no | `artifacts/release-evidence.json` |
| `build-template.R` | Regenerate `inst/templates/DCC-cleaning-plan.xlsx`. Maintainer only; needs devtools. | no | no | `inst/templates/` in the checkout |
| `check-benchmarks.R` | Compare captured benchmarks against `benchmarks/baseline.json`. | sourced only | no | nothing (reads and reports) |
| `ci-install-locked.R` | **CI only.** Pin the CI library to the `renv.lock` closure via pak. | no | **yes, in CI** | the CI job's library |
| `classify-r-check.R` | Parse a `00check.log` into pass/fail evidence. | sourced only | no | `artifacts/r-check.json` |
| `coverage-report.R` | Summarise covr output per area. | sourced only | no | `artifacts/coverage.{json,html}` |
| `generate-format-fixtures.R` | Regenerate the format test fixtures and their manifest. | no | no | `tests/fixtures/formats/` in the checkout |
| `run-acceptance.R` | Drive the acceptance suites and record evidence. | read as text only | no | `artifacts/acceptance/` |
| `run-release-tests.R` | Run testthat repeatedly and record the result. | no | no | `artifacts/release-tests.json` |
| `verify-dependencies.R` | Audit that `R/` declares every namespace it uses and installs nothing. | sourced only | no | nothing (reads and reports) |
| `verify-format-matrix.R` | Verify each format fixture still reads to the recorded hash. | yes, `--local` subprocess | no | nothing unless `--output` is given |
| `verify-release.R` | Validate a release-evidence document against the release contract. | sourced only | no | nothing (reads and reports) |

`benchmarks/baseline.json` is recorded data, not code.

### About `ci-install-locked.R` and `build-internal-bundle.R`

These are the only two files here that mention installation, so to be explicit:

* `ci-install-locked.R` calls `pak::pkg_install()` to reinstall the packages
  recorded in `renv.lock` at their locked versions. It is invoked from
  `.github/workflows/` and acts on the CI runner's own library. It is not
  referenced by `R/`, `tests/`, `man/`, or `vignettes/`, and it does nothing on
  `source()`.
* `build-internal-bundle.R` installs nothing. It *writes out a text file*
  (`install-DCC.R`) into an offline bundle directory so that an internal user
  who has no network can later run it themselves against a library path they
  choose. The `install.packages(...)` text CRAN's scan sees is that generated
  file's content, in a string literal — never a call this package makes.

`artifacts/`, `examples/`, `docs/`, and `renv.lock` are listed in
`.Rbuildignore`, so the outputs above are development materials and are not
part of the CRAN tarball.
