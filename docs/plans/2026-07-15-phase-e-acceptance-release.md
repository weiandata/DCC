# Phase E Acceptance and Release Implementation Plan

> **Execution:** Complete the checked tasks in order, with the stated red/green
> verification and review checkpoint before each commit.

**Goal:** Prove that DCC is robust and usable by survey staff, statisticians,
and AI agents across supported operating systems, input formats, encodings, and
failure conditions, then produce reproducible CRAN and internal releases.

**Architecture:** Acceptance is evidence, not a final manual spot-check. CI
combines unit, property, fault-injection, format-matrix, performance, and
persona contract suites. One release verifier consumes those artifacts and
refuses release when a promised capability lacks passing evidence.

**Tech Stack:** R >= 4.1, testthat, covr, GitHub Actions, pak for CI dependency
resolution, renv lockfile for the internal bundle, shell/R release scripts.

## Global Constraints

- Phases A through D are complete.
- Formal capability levels are `Stable`, `Experimental`, and `Unavailable`.
- Every `Stable` format passes Linux, macOS, and Windows fixtures.
- XLSB remains `Experimental` until its documented feature matrix passes all
  three platforms; it cannot block the core release.
- All formal format dependencies install with DCC; runtime auto-install is
  forbidden.
- Release evidence uses synthetic or explicitly approved data only.
- PDF is outside the mandatory release gate.
- Before each commit, stage exactly the files listed for that task.

---

### Task 1: Add property, migration, and fault-injection tests

**Files:**
- Create: `tests/testthat/test-property-roundtrip.R`
- Create: `tests/testthat/test-fault-injection.R`
- Create: `tests/testthat/test-backward-compatibility.R`
- Create: `tests/testthat/helper-generators.R`
- Modify: `DESCRIPTION`
- Modify: `.Rbuildignore`

- [ ] **Step 1: Define generated-data invariants**

```r
test_that("preview and apply reconcile for generated surveys", {
  for (seed in seq_len(100L)) {
    x <- generated_survey(seed)
    preview <- dcc_preview(x$data, x$config)
    applied <- dcc_execute(x$data, x$config)
    expect_equal(preview$summary$planned_actions,
                 applied$summary$applied_actions)
    expect_equal(applied$reconciliation$input_rows,
                 applied$reconciliation$output_rows +
                   applied$reconciliation$removed_rows)
  }
})
```

Cover empty tables, all-missing columns, labeled values, tagged missing values,
duplicate names, extreme numerics, Unicode, multiselect columns, zero matches,
and repeated execution. Generated failing cases must print their seed.

- [ ] **Step 2: Add migration tests for public legacy calls**

Snapshot public function signatures and prove legacy `dcc_read()`,
`dcc_run(data, config, ...)`, detector IDs, and report calls either still work
or emit the documented lifecycle warning.

- [ ] **Step 3: Add deterministic failure injection**

Inject unreadable inputs, malformed workbooks, exhausted disk staging, write
permission errors, renderer failure, schema corruption, interrupted publication,
and unavailable experimental backends. Assert stable codes and manifest states.

- [ ] **Step 4: Run tests repeatedly**

```sh
Rscript -e 'for (i in 1:5) devtools::test(filter="property|fault|backward", reporter="summary")'
```

- [ ] **Step 5: Commit**

Commit: `git commit -m "test: add property and fault acceptance suites"`

---

### Task 2: Build the three-platform format and encoding matrix

**Files:**
- Create: `.github/workflows/format-matrix.yml`
- Create: `tests/fixtures/formats/README.md`
- Create: `tests/fixtures/formats/manifest.json`
- Create: `tools/generate-format-fixtures.R`
- Create: `tools/verify-format-matrix.R`
- Create: `tests/testthat/test-format-matrix.R`
- Modify: `.gitattributes`

- [ ] **Step 1: Define fixture provenance and expected hashes**

The manifest records generator version, source hash, format, compression,
encoding, locale, expected canonical hash, expected labels, expected missing
states, and capability level. Commit small deterministic fixtures; generate
large fixtures in CI.

- [ ] **Step 2: Generate the supported matrix**

At minimum include CSV/TSV/TXT using UTF-8, UTF-8 BOM, UTF-16LE/BE,
GB18030/GBK, Big5, Shift-JIS, Windows-1252, and Latin-1; XLS/XLSX/ODS;
JSON/JSONL; RDS; SAV/POR/DTA/SAS7BDAT/XPT; Parquet/Feather; gzip/bzip2/xz/zip
where the selected adapter supports compression.

- [ ] **Step 3: Add the OS matrix**

Run released R on `ubuntu-latest`, `macos-latest`, and `windows-latest`, plus
R-devel on Linux for core checks. Install the package once and run
`tools/verify-format-matrix.R` without installing a backend at runtime.

- [ ] **Step 4: Enforce capability truthfulness**

`Stable` requires identical canonical hashes on all three platforms.
`Experimental` records outcomes but cannot appear as stable in
`dcc_capabilities()`. `Unavailable` must return an actionable diagnostic.

- [ ] **Step 5: Run local available-platform verification**

Run: `Rscript tools/verify-format-matrix.R --local`

- [ ] **Step 6: Commit**

Commit: `git commit -m "ci: verify format and encoding support"`

---

### Task 3: Establish performance and memory release gates

**Files:**
- Modify: `tools/benchmarks/benchmark.R`
- Create: `tools/benchmarks/memory.R`
- Create: `tools/benchmarks/baseline.json`
- Create: `tools/check-benchmarks.R`
- Create: `.github/workflows/benchmark.yml`
- Create: `tests/testthat/test-benchmark-contract.R`

- [ ] **Step 1: Separate benchmark stages**

Measure import, canonicalization, validation, detection, preview, execution,
report modeling, and each renderer separately. Record rows, columns, findings,
actions, elapsed time, peak memory, R/platform, CPU class, and package versions.

- [ ] **Step 2: Define release thresholds**

For the fixed one-million-row synthetic benchmark, require no correctness
failure, no unbounded memory growth, and no stage regression above 20% relative
to the accepted platform baseline. The published 60-second execution budget
also requires at least 25% headroom: median execution must be at most 45 seconds
on the reference runner. A release cannot claim this gate until it is measured.

- [ ] **Step 3: Add robust comparison logic**

Use medians from at least three runs, compare only like-for-like platform
classes, fail on missing stage records, and print both absolute and relative
changes. Baseline updates require review and a written reason.

- [ ] **Step 4: Run local benchmarks**

```sh
Rscript tools/benchmarks/benchmark.R --runs=3
Rscript tools/benchmarks/memory.R
Rscript tools/check-benchmarks.R --baseline=tools/benchmarks/baseline.json
```

- [ ] **Step 5: Commit**

Commit: `git commit -m "perf: add time and memory release gates"`

---

### Task 4: Create acceptance suites for all three audiences

**Files:**
- Create: `tests/acceptance/staff/README.md`
- Create: `tests/acceptance/staff/scenarios.yml`
- Create: `tests/acceptance/statistician/README.md`
- Create: `tests/acceptance/statistician/scenarios.yml`
- Create: `tests/acceptance/agent/tasks.json`
- Create: `inst/schemas/agent-task-result.schema.json`
- Create: `tools/run-acceptance.R`
- Create: `docs/acceptance/scoring.md`

- [ ] **Step 1: Define staff scenarios and scoring**

Test template download, workbook completion, invalid-cell correction,
`dcc_check()`, preview, apply, and report interpretation. At least 80% of
participants must complete template, check, preview, and export within 30
minutes; at least 80% must distinguish preview from execution; nobody modifies
R code; raw-file overwrites are zero; median System Usability Scale score is at
least 75. Use synthetic surveys and record timing per scenario.

- [ ] **Step 2: Define statistician scenarios and scoring**

Test programmatic import, labeled/tagged missing preservation, custom rules,
preview/apply reconciliation, reproducibility, full-table exports, provenance,
and legacy migration. Require all correctness assertions and documented caveats.

- [ ] **Step 3: Define AI-agent tasks and schema**

Create at least 20 deterministic tasks covering capability discovery, strict
plan construction, validation error recovery, preview/apply, artifact lookup,
schema validation, and machine-summary interpretation. Each task has allowed
public calls, expected stable codes, artifact assertions, and a bounded result.
At least 90% must succeed within two attempts; every execution validates and
previews first, and ambiguous inputs must be corrected or refused.

- [ ] **Step 4: Implement a non-interactive runner**

```sh
Rscript tools/run-acceptance.R --audience=staff --mode=synthetic
Rscript tools/run-acceptance.R --audience=statistician --mode=synthetic
Rscript tools/run-acceptance.R --audience=agent --mode=contract
```

The staff suite emits a facilitator worksheet for real usability sessions; it
does not pretend an automated script is evidence of human usability.

- [ ] **Step 5: Commit**

Commit: `git commit -m "test: add three-audience acceptance suites"`

---

### Task 5: Make dependency and installation promises verifiable

**Files:**
- Modify: `DESCRIPTION`
- Create: `renv.lock`
- Create: `tools/verify-dependencies.R`
- Create: `tools/build-internal-bundle.R`
- Create: `docs/installation.md`
- Create: `.github/workflows/install.yml`

- [ ] **Step 1: Audit dependency placement**

Every package required for a formally supported format belongs in `Imports`.
Keep only development, vignette, testing, and experimental backends in
`Suggests`. Reject undeclared `pkg::fun` calls and runtime installation code.

- [ ] **Step 2: Test clean one-command installation**

Build the source package, install it with dependencies into an empty library,
then run `dcc_doctor()` and the supported-format smoke suite without network
access. Repeat on Linux, macOS, and Windows CI.

- [ ] **Step 3: Build the internal bundle**

Create a versioned source tarball, dependency lockfile, package repository
index, checksums, license inventory, install script, and verification report.
The bundle contains no user data and does not fork DCC into a second package.

- [ ] **Step 4: Document CRAN and internal installation**

State which formats are supported or experimental, disk-space expectations,
offline installation steps, and how `dcc_doctor()` diagnoses missing system
capabilities.

- [ ] **Step 5: Commit**

Commit: `git commit -m "build: verify complete DCC installations"`

---

### Task 6: Add the release evidence verifier

**Files:**
- Create: `tools/verify-release.R`
- Create: `inst/schemas/release-evidence.schema.json`
- Create: `.github/workflows/r-check.yml`
- Create: `.github/workflows/coverage.yml`
- Create: `cran-comments.md`
- Create: `docs/release-checklist.md`
- Modify: `NEWS.md`

- [ ] **Step 1: Define required evidence**

Require R check results, coverage, supported-format matrix, property/fault
tests, benchmark comparison, staff/statistician/agent acceptance results,
dependency audit, schema validation, and artifact hashes. Human staff testing
may be recorded as an approved signed result rather than fabricated by CI.

- [ ] **Step 2: Implement one verifier**

```r
evidence <- dcc_read_release_evidence(commandArgs(trailingOnly = TRUE)[1L])
dcc_validate_release_evidence(evidence)
dcc_assert_release_gate(evidence)
cat("DCC release evidence: PASS\n")
```

The verifier exits non-zero for stale, missing, failed, or capability-mismatched
evidence and prints the exact missing gate.

- [ ] **Step 3: Add coverage and package checks**

Require full `R CMD check --as-cran` on the release candidate with zero errors,
warnings, and notes; zero test failures, warnings, and skips in the complete
release image; overall line coverage of at least 90%; and at least 95% for
import, validation, rules, execution, audit, rerun, and report-model code.

- [ ] **Step 4: Prepare CRAN and internal release artifacts**

Record incoming-check notes honestly, exclude internal-only material from the
CRAN tarball, verify both artifacts share the same DCC source version, and sign
or checksum every distributed file.

- [ ] **Step 5: Run the final gate**

```sh
Rscript -e 'devtools::test(reporter="summary")'
R CMD build .
R CMD check --as-cran DCC_*.tar.gz
Rscript tools/verify-release.R artifacts/release-evidence.json
```

- [ ] **Step 6: Commit**

Commit: `git commit -m "release: add evidence-based DCC gate"`

## Phase E Exit Criteria

- Stable formats and encodings pass the three-platform canonical hash matrix.
- Property, migration, and fault-injection suites pass repeatedly.
- Time and peak-memory results are compared to reviewed baselines.
- One-million-row execution has at least 25% headroom against its 60-second budget.
- Staff, statistician, and AI-agent acceptance evidence meets documented gates.
- A clean install includes every formal format backend and passes offline smoke tests.
- CRAN and internal bundles come from the same source and include verifiable hashes.
- The release verifier reports PASS with no missing or stale evidence.
