# Stable Hosted Benchmark Gate Design

## Goal

Remove the systematic false failures in DCC's GitHub-hosted performance
workflow without weakening CRAN checks, correctness checks, evidence
integrity, memory limits, or the 45-second execution budget.

## Evidence and Root Cause

The current `main` commit passes all four `R CMD check --as-cran` jobs,
coverage, installation, format, and repository checks. The only failing job is
the one-million-row benchmark's accepted-baseline comparison.

The benchmark capture succeeds, all correctness assertions succeed, and the
separate memory ceiling succeeds. Across the latest eleven GitHub-hosted
macOS ARM64 runs, capture duration ranged from 191 to 321 seconds while the
package code exercised by the benchmark was unchanged for most of those
commits. Ten runs failed the 20% relative comparison and one passed. A local
three-run reproduction on Darwin ARM64 with R 4.6 passed correctness, memory,
the relative comparison, and the 45-second execution budget.

The root cause is therefore the use of a 20% hard relative-time threshold on
variable shared GitHub runner capacity. It is not evidence of a deterministic
DCC performance regression.

## Selected Design

`compare_benchmarks()` will distinguish hard failures from advisory findings.
Its existing strict behavior remains the default so direct callers and stable
hardware reviews still reject relative time regressions.

When `strict_relative = FALSE`, a relative time increase above the accepted
threshold is recorded as `BENCHMARK_REGRESSION` in an `advisories` table
instead of the `failures` table. The GitHub-hosted benchmark workflow will use
this mode.

The following conditions remain hard failures in every mode:

- invalid current or baseline evidence contracts;
- platform or CPU-class mismatch;
- missing benchmark stages;
- fewer than three runs;
- failed correctness assertions;
- relative memory regression above the accepted limit;
- execution-stage median above 45 seconds;
- non-finite timing or memory evidence.

The command-line tool will print both the comparison table and any advisory
relative regressions. A hosted run with only relative-time advisories exits
successfully and prints `BENCHMARK: PASS WITH ADVISORIES`. Strict mode
continues to print `BENCHMARK: FAIL` and exit non-zero for the same evidence.

## Configuration

The accepted baseline remains the source of `regression_limit`,
`execution_budget_seconds`, and `minimum_runs`. The command-line tool will
read these values from `tools/benchmarks/baseline.json` rather than silently
using duplicated defaults.

The GitHub workflow will invoke:

```sh
Rscript tools/check-benchmarks.R \
  --current=artifacts/benchmark-current.json \
  --baseline=tools/benchmarks/baseline.json \
  --strict-relative=false
```

Strict review remains available by omitting `--strict-relative=false`.

Release evidence contract 1.1 records `comparison_mode` as either `strict` or
`hosted_advisory`. The release verifier applies the 20% relative-time limit
only to strict evidence. Both modes continue to require one million rows,
three runs, execution median at or below 45 seconds, and passing memory
evidence.

## Tests

The benchmark contract tests will prove:

1. strict comparison still rejects a 30% time regression;
2. hosted mode reports the same regression as an advisory and succeeds;
3. hosted mode still fails an execution median above 45 seconds;
4. hosted mode still fails memory regressions, incomplete evidence, unlike
   platforms or CPUs, insufficient repetitions, and failed correctness;
5. baseline policy fields are present and used by the command-line path.

The regression test will be written and observed failing before the
implementation changes.

## Documentation

The release checklist will describe relative timing on shared hosted runners
as reviewed evidence rather than a deterministic hard gate. It will continue
to require three correctness-valid million-row runs, a passing memory report,
and execution median at or below 45 seconds.

`NEWS.md` will record the CI reliability correction.

## Verification and Completion

Before pushing, run:

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-benchmark-contract.R")'
Rscript tools/check-benchmarks.R \
  --current=/tmp/dcc-ci-artifacts/benchmark-current.json \
  --baseline=tools/benchmarks/baseline.json \
  --strict-relative=false
Rscript tools/run-release-tests.R --runs=1
R CMD build --no-manual .
R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz
```

After push, monitor every workflow on the resulting commit. Completion
requires no failed GitHub checks and all four `--as-cran` matrix jobs passing.
