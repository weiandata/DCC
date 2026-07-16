# DCC 1.2.0 release checklist

The checklist is evidence-driven. A checked box must point to a signed or
hashed artifact; running a preparation script is not itself a pass.

## Candidate identity

- [ ] `DESCRIPTION`, CRAN tarball, and internal bundle have one release version.
- [ ] Candidate commit and capability document are frozen.
- [ ] CRAN tarball and internal bundle SHA-256 values are recorded and verified.
- [ ] Internal bundle report says `contains_user_data: false`.

## Automated correctness

- [ ] Full release-image tests have zero failures, warnings, and skips.
- [ ] Property, migration, and fault suites pass five consecutive runs.
- [ ] `R CMD check --as-cran` has zero errors and warnings, zero actionable NOTEs;
      the only permitted NOTE code is `cran_new_submission`.
- [ ] Overall coverage is at least 90%; import, validation, rules, execution,
      audit, rerun, and report-model areas are each at least 95%.
- [ ] All published JSON schemas validate their examples and generated bundles.

## Formats, performance, and installation

- [ ] Stable formats have identical semantic hashes on Linux, macOS, and Windows.
- [ ] No format with external-required evidence is marked Stable.
- [ ] The reviewed one-million-row benchmark has at least three runs, no stage
      regression above 20%, execution median at most 45 seconds, and a passing
      memory report.
- [ ] Dependency audit has no undeclared or runtime installer calls.
- [ ] Clean installs and offline smoke tests pass on Linux, macOS, and Windows.
- [ ] Complete internal repository contains DCC plus the exact locked dependency
      sources, repository index, lockfile, licenses, install script, and checksums.

## Three audiences

- [ ] At least five target staff participants supply signed records.
- [ ] Staff completion and preview/execute distinction rates are at least 80%,
      median SUS is at least 75, code edits are zero, and raw overwrites are zero.
- [ ] All eight statistician correctness scenarios pass with written caveats.
- [ ] At least 90% of the 20+ Agent tasks succeed within two attempts.
- [ ] Every Agent execution validates and previews first; unsafe executions are
      zero and ambiguous inputs are corrected or refused.

## Final commands

```sh
Rscript tools/verify-dependencies.R
Rscript tools/run-release-tests.R --runs=1 --output=artifacts/release-tests.json
Rscript tools/run-release-tests.R '--filter=property|fault|backward' --runs=5 \
  --output=artifacts/property-fault.json
Rscript tools/benchmarks/benchmark.R --rows=1000000 --runs=3
Rscript tools/benchmarks/memory.R
R CMD build .
R CMD check --as-cran DCC_*.tar.gz
Rscript tools/verify-release.R artifacts/release-evidence.json
```

Release only when the final command prints `DCC release evidence: PASS` with
fresh evidence. `facilitator_required`, `contract_pass`, missing CI platforms,
unknown/actionable NOTEs, or a NOTE count mismatch are blocking states.
