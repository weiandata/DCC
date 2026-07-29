# CRAN submission comments

## Resubmission

This is a resubmission. Following the review of the 2026-07-17 submission:

* `DESCRIPTION` no longer single-quotes file-format and markup names (CSV,
  Parquet, JSON, JSONL, YAML, HTML, PDF) or the package's own `dcc_data`
  container. Only third-party software names ('Excel', 'SPSS', 'Stata',
  'SAS') remain quoted.
* No exported function has a default write path any more. `dcc_check()`,
  `dcc_run()`, and `dcc_template()` previously defaulted to `"dcc-check"`,
  `"dcc-results"`, and `"DCC-cleaning-plan.xlsx"` relative to `getwd()`;
  the destination is now a required argument and calling without it raises
  an error that points to `tempdir()`. Every other file-writing function
  (`dcc_report()`, `dcc_export_log()`, `dcc_manifest()`,
  `dcc_report_staff()`, `dcc_report_statistical()`,
  `dcc_report_machine()`, `dcc_write_config_template()`) already required an
  explicit path.
* All examples, tests, and vignettes write only under `tempdir()`; the
  remaining vignette chunk that showed a relative output directory now uses
  `file.path(tempdir(), "dcc-run")`.

## Submission status

This is the candidate record for DCC 1.2.1. Do not submit until
`docs/release-checklist.md` is complete and `tools/verify-release.R` reports
PASS from fresh evidence. `DESCRIPTION` is frozen at version 1.2.1.

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
any other NOTE, or any count mismatch remains blocking. Results are not
claimed here before the CI artifacts exist.

`DCC_1.2.1.tar.gz` was additionally checked on win-builder:

* Windows, R Under development (unstable) (2026-07-28 r90311 ucrt): Status 1 NOTE
* Windows, R 4.6.1 (2026-06-24 ucrt): Status 1 NOTE

In both runs the only NOTE is the incoming-feasibility NOTE: new submission
plus the possibly-misspelled words discussed under "Spelling". There were no
errors and no warnings.

## Package scope and dependencies

DCC cleans survey and assessment response data. All declared input-format
backends are ordinary `Imports` and install with DCC. No package is installed
at runtime. Arrow is included because Parquet and Feather are declared input
formats; PDF remains optional and is not a fixed output.

The package writes files only when the caller requests a template, run, report,
or export. Examples and tests use temporary directories and synthetic data.
The internal offline bundle, dependency lock, acceptance records, benchmarks,
and release evidence are build/review materials rather than a second DCC
package.

## Incoming checks

URLs and external references must be rechecked on the final source tarball.
Any platform limitation or unavailable external fixture is reported as a
capability/evidence limitation, not described as a passing Stable result.

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
