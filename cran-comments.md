## Submission status

This is a preparatory file for DCC 1.2.0. Do not submit until
`docs/release-checklist.md` is complete and `tools/verify-release.R` reports
PASS from fresh evidence. The development version currently remains
1.2.0.9000 and is not a CRAN release candidate.

## Test environments

The release workflow is configured for:

* Ubuntu, R devel
* Ubuntu, R release
* macOS, R release
* Windows, R release

Every release-candidate check uses `--as-cran` and treats a NOTE as failure.
Final error, warning, NOTE, test warning, failure, and skip counts must all be
zero. Results are intentionally not claimed here before those CI artifacts
exist.

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
