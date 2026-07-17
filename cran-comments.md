# CRAN submission comments

## Submission status

This is the candidate record for DCC 1.2.0. Do not submit until
`docs/release-checklist.md` is complete and `tools/verify-release.R` reports
PASS from fresh evidence. `DESCRIPTION` is frozen at version 1.2.0.

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

The incoming feasibility check flags "WeianData", "backends", and "preflight"
in `DESCRIPTION` as possibly misspelled. All three are intentional and spelled
correctly: "WeianData" is the copyright holder's company name, and "backends"
and "preflight" are standard technical terms used as written.
