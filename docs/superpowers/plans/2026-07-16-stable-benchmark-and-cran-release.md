# Stable Benchmark and CRAN Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DCC's GitHub-hosted benchmark reliable, obtain an all-green GitHub commit, build a CRAN-ready DCC 1.2.0 source package, and publish a detailed release procedure.

**Architecture:** The benchmark comparator retains strict relative-time enforcement by default but can classify relative-time regressions as advisories on variable shared runners. Correctness, evidence compatibility, repetition count, memory regression, memory ceilings, and the 45-second execution budget remain hard gates. Release verification builds and checks the exact source archive from the green commit and records its checksum.

**Tech Stack:** R 4.6, testthat 3, jsonlite, GitHub Actions, GitHub REST API/CLI, `R CMD build`, `R CMD check --as-cran`.

## Global Constraints

- DCC remains version `1.2.0`.
- All four GitHub `R CMD check --as-cran` matrix jobs must pass.
- The only permitted CRAN NOTE is the first-submission `cran_new_submission` classification.
- Errors, warnings, test failures, test warnings, and test skips must be zero.
- Relative timing on shared GitHub runners may be advisory; correctness, contract, platform/CPU compatibility, minimum runs, memory, and the 45-second execution budget remain blocking.
- Release evidence must record whether benchmark comparison used `strict` or `hosted_advisory` mode; only strict mode requires `maximum_regression <= 0.2`.
- No runtime dependency or installer behavior is added.
- Final artifacts must be built from the same commit that is green on GitHub.
- Existing untracked release artifacts belong to the user and must not be deleted or overwritten without necessity.

---

### Task 1: Add the hosted-runner regression tests

**Files:**
- Modify: `tests/testthat/test-benchmark-contract.R`

**Interfaces:**
- Consumes: `compare_benchmarks(current, baseline, regression_limit, execution_budget, minimum_runs, strict_relative)`.
- Produces: tests that distinguish strict relative failures from hosted-runner advisories while preserving all hard gates.

- [ ] **Step 1: Add a failing hosted-runner advisory test**

Add:

```r
test_that("hosted benchmark mode makes relative time noise advisory", {
  source(benchmark_tool, local = TRUE)
  stages <- benchmark_required_stages()
  baseline <- data.frame(
    platform_class = "Darwin-aarch64-R4.6", cpu_class = "GitHub ARM64",
    stage = stages, median_seconds = rep(10, length(stages)),
    peak_memory_bytes = rep(1e8, length(stages)), stringsAsFactors = FALSE
  )
  current <- do.call(rbind, lapply(seq_len(3L), function(run) {
    data.frame(
      platform_class = "Darwin-aarch64-R4.6", cpu_class = "GitHub ARM64",
      run = run, stage = stages, seconds = rep(13, length(stages)),
      peak_memory_bytes = rep(1e8, length(stages)), correctness = TRUE,
      stringsAsFactors = FALSE
    )
  }))

  hosted <- compare_benchmarks(current, baseline, strict_relative = FALSE)
  expect_true(hosted$ok)
  expect_false(nrow(hosted$failures) > 0L)
  expect_setequal(unique(hosted$advisories$code), "BENCHMARK_REGRESSION")

  current$seconds[current$stage == "execution"] <- 46
  over_budget <- compare_benchmarks(
    current, baseline, strict_relative = FALSE
  )
  expect_false(over_budget$ok)
  expect_true("BENCHMARK_EXECUTION_BUDGET" %in% over_budget$failures$code)
})
```

- [ ] **Step 2: Add a hard-memory-gate assertion in hosted mode**

Add to the same test:

```r
current$seconds <- 10
current$peak_memory_bytes[current$stage == "machine"] <- 1.3e8
memory_regression <- compare_benchmarks(
  current, baseline, strict_relative = FALSE
)
expect_false(memory_regression$ok)
expect_true(
  "BENCHMARK_MEMORY_REGRESSION" %in% memory_regression$failures$code
)
```

- [ ] **Step 3: Run the focused test and observe the expected failure**

Run:

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-benchmark-contract.R")'
```

Expected: failure because `compare_benchmarks()` has no
`strict_relative` argument or `advisories` result.

---

### Task 2: Implement strict and hosted comparison modes

**Files:**
- Modify: `tools/check-benchmarks.R`
- Modify: `.github/workflows/benchmark.yml`
- Test: `tests/testthat/test-benchmark-contract.R`
- Modify: `tools/verify-release.R`
- Modify: `inst/schemas/release-evidence.schema.json`
- Modify: `tests/testthat/test-release-evidence.R`
- Modify: `docs/superpowers/specs/2026-07-16-stable-hosted-benchmark-gate-design.md`

**Interfaces:**
- Consumes: current benchmark records and accepted baseline fields.
- Produces: `compare_benchmarks(..., strict_relative = TRUE)` returning
  `list(ok, comparison, failures, advisories)`.

- [ ] **Step 1: Add advisory records and strict-mode selection**

Update the function signature and collectors:

```r
compare_benchmarks <- function(current, baseline, regression_limit = 0.20,
                               execution_budget = 45, minimum_runs = 3L,
                               strict_relative = TRUE) {
  failures <- list()
  advisories <- list()
  add_failure <- function(code, stage = NA_character_, detail = "") {
    failures[[length(failures) + 1L]] <<-
      benchmark_failure(code, stage, detail)
  }
  add_advisory <- function(code, stage = NA_character_, detail = "") {
    advisories[[length(advisories) + 1L]] <<-
      benchmark_failure(code, stage, detail)
  }
```

For finite relative timing above the limit:

```r
if (!is.finite(relative)) {
  add_failure("BENCHMARK_TIME_INVALID", stage, "non-finite median or baseline")
} else if (relative > regression_limit) {
  recorder <- if (isTRUE(strict_relative)) add_failure else add_advisory
  recorder(
    "BENCHMARK_REGRESSION", stage,
    sprintf("time change %.1f%% exceeds %.1f%%", 100 * relative,
            100 * regression_limit)
  )
}
```

Return an empty, typed advisory table when there are no advisories.

- [ ] **Step 2: Make the CLI read policy from the accepted baseline**

Add:

```r
benchmark_logical_argument <- function(args, name, default = TRUE) {
  value <- tolower(benchmark_argument(args, name, as.character(default)))
  if (value %in% c("true", "1", "yes")) return(TRUE)
  if (value %in% c("false", "0", "no")) return(FALSE)
  stop("--", name, " must be true or false.")
}
```

In `main()`:

```r
strict_relative <- benchmark_logical_argument(
  args, "strict-relative", default = TRUE
)
result <- compare_benchmarks(
  current$records,
  baseline$stages,
  regression_limit = as.numeric(baseline$regression_limit),
  execution_budget = as.numeric(baseline$execution_budget_seconds),
  minimum_runs = as.integer(baseline$minimum_runs),
  strict_relative = strict_relative
)
```

Print advisories before evaluating hard failures. If only advisories remain,
print `BENCHMARK: PASS WITH ADVISORIES`; otherwise preserve `BENCHMARK: PASS`
or `BENCHMARK: FAIL`.

- [ ] **Step 3: Configure GitHub-hosted comparison mode**

Change `.github/workflows/benchmark.yml`:

```yaml
      - name: Compare accepted like-for-like baseline
        run: >-
          Rscript tools/check-benchmarks.R
          --current=artifacts/benchmark-current.json
          --baseline=tools/benchmarks/baseline.json
          --strict-relative=false
```

- [ ] **Step 4: Run the focused tests**

Run:

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-benchmark-contract.R")'
```

Expected: all benchmark contract tests pass.

- [ ] **Step 5: Make release evidence record the comparison mode**

Add required benchmark field `comparison_mode` with allowed values `strict`
and `hosted_advisory`. Bump the closed release-evidence contract and schema
ID from `1.0` to `1.1`.

Update the release fixture:

```r
contract_version = "1.1"
```

and:

```r
benchmark = list(
  status = "pass", rows = 1e6, runs = 3L,
  execution_median_seconds = 8.9, maximum_regression = 0.1,
  comparison_mode = "strict", memory_status = "pass"
)
```

Add a test proving hosted advisory evidence remains releasable while strict
evidence above 20% remains blocking:

```r
test_that("release benchmark policy distinguishes strict and hosted timing", {
  source(release_tool, local = TRUE)
  root <- dcc_source_root()
  now <- as.POSIXct("2026-07-16 12:00:00", tz = "UTC")
  evidence <- release_evidence_fixture(root)
  evidence$gates$benchmark$maximum_regression <- 0.8
  evidence$gates$benchmark$comparison_mode <- "hosted_advisory"
  expect_equal(nrow(dcc_validate_release_evidence(evidence, root, now)), 0L)

  evidence$gates$benchmark$comparison_mode <- "strict"
  strict <- dcc_validate_release_evidence(evidence, root, now)
  expect_true("RELEASE_BENCHMARK_FAILED" %in% strict$code)
})
```

In `tools/verify-release.R`, keep rows, runs, execution, and memory hard in
both modes, and require `maximum_regression <= 0.2` only when
`comparison_mode == "strict"`.

Update the approved design document to state this release-evidence rule.

- [ ] **Step 6: Run all focused benchmark and release-evidence tests**

Run:

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-benchmark-contract.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-release-evidence.R")'
```

Expected: all focused tests pass.

- [ ] **Step 7: Exercise both CLI modes with synthetic evidence**

Run hosted mode:

```sh
Rscript tools/check-benchmarks.R \
  --current=/tmp/dcc-ci-artifacts/benchmark-current.json \
  --baseline=tools/benchmarks/baseline.json \
  --strict-relative=false
```

Expected: exit 0 and `BENCHMARK: PASS` or
`BENCHMARK: PASS WITH ADVISORIES`.

Run strict mode by omitting the final argument. Expected: exit 0 for the
current local evidence.

- [ ] **Step 8: Commit the tested implementation**

```sh
git add tests/testthat/test-benchmark-contract.R \
  tests/testthat/test-release-evidence.R tools/check-benchmarks.R \
  tools/verify-release.R inst/schemas/release-evidence.schema.json \
  .github/workflows/benchmark.yml \
  docs/superpowers/specs/2026-07-16-stable-hosted-benchmark-gate-design.md
git commit -m "fix: stabilize hosted benchmark gate"
```

---

### Task 3: Document the corrected release policy and procedure

**Files:**
- Modify: `NEWS.md`
- Modify: `docs/release-checklist.md`
- Create: `docs/cran-release-process.md`

**Interfaces:**
- Consumes: DCC 1.2.0 release requirements and the new benchmark modes.
- Produces: a detailed, executable CRAN release procedure with commands,
  expected evidence, GitHub gates, submission steps, and post-submission
  checks.

- [ ] **Step 1: Update release policy wording**

Replace the benchmark checklist requirement with:

```markdown
- [ ] The reviewed one-million-row benchmark has at least three
      correctness-valid runs, execution median at most 45 seconds, and a
      passing memory report. Relative timing changes from shared GitHub
      runners are reviewed as advisories; strict relative comparison is run
      only on stable like-for-like hardware.
```

- [ ] **Step 2: Record the CI correction in NEWS**

Add a DCC 1.2.0 bullet explaining that hosted-runner relative timing is
advisory while hard correctness, memory, and execution budgets remain
blocking.

- [ ] **Step 3: Write the detailed CRAN release process**

Create `docs/cran-release-process.md` with these complete sections:

1. prerequisites and required credentials;
2. freeze and clean-worktree checks;
3. dependency and release-test commands;
4. benchmark strict/hosted interpretation;
5. `R CMD build --no-manual .`;
6. `R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz`;
7. exact NOTE classification policy;
8. GitHub matrix requirements;
9. SHA-256 recording and artifact identity;
10. CRAN web submission fields and `cran-comments.md`;
11. incoming-check response procedure;
12. post-acceptance tag/release/archive steps;
13. rollback and re-submission rules.

Every shell step must include the expected success condition and the files
that should be retained.

- [ ] **Step 4: Verify Markdown style**

Run:

```sh
npx --yes markdownlint-cli2 \
  NEWS.md docs/release-checklist.md docs/cran-release-process.md
```

Expected: zero Markdown errors.

- [ ] **Step 5: Commit the documentation**

```sh
git add NEWS.md docs/release-checklist.md docs/cran-release-process.md
git commit -m "docs: define CRAN release procedure"
```

---

### Task 4: Run local release verification and build the candidate

**Files:**
- Generated: `DCC_1.2.0.tar.gz`
- Generated: `DCC.Rcheck/`
- Generated: `artifacts/release/DCC_1.2.0.sha256`

**Interfaces:**
- Consumes: the exact candidate source tree after Tasks 1–3.
- Produces: a locally verified CRAN source archive and checksum.

- [ ] **Step 1: Run focused and full release tests**

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-benchmark-contract.R")'
Rscript tools/run-release-tests.R \
  --runs=1 --output=artifacts/release-tests-final.json
Rscript tools/run-release-tests.R \
  '--filter=property|fault|backward' --runs=5 \
  --output=artifacts/property-fault-final.json
```

Expected: zero failures, warnings, and skips in both JSON artifacts.

- [ ] **Step 2: Verify dependencies and build inputs**

```sh
Rscript tools/verify-dependencies.R
git diff --check
```

Expected: dependency verification passes and `git diff --check` exits 0.

- [ ] **Step 3: Build the CRAN source package**

```sh
R CMD build --no-manual .
```

Expected: creates `DCC_1.2.0.tar.gz`.

- [ ] **Step 4: Run the CRAN check on the built archive**

```sh
R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz
```

Expected: zero errors, zero warnings, and only the permitted first-submission
NOTE.

- [ ] **Step 5: Classify the check result**

```sh
Rscript tools/classify-r-check.R \
  --log=DCC.Rcheck \
  --output=artifacts/release/r-check-final.json
```

Expected: status passes with only `cran_new_submission` allowed.

- [ ] **Step 6: Record the archive checksum**

```sh
shasum -a 256 DCC_1.2.0.tar.gz \
  > artifacts/release/DCC_1.2.0.sha256
```

Expected: one SHA-256 line naming `DCC_1.2.0.tar.gz`.

---

### Task 5: Push and monitor GitHub until all checks pass

**Files:**
- Remote evidence only: GitHub Actions runs and artifacts for the pushed commit.

**Interfaces:**
- Consumes: committed implementation and documentation.
- Produces: one remote `main` commit with every check successful.

- [ ] **Step 1: Push the candidate commits**

```sh
git push origin main
```

Expected: remote `main` advances to the local candidate commit.

- [ ] **Step 2: Monitor every workflow and matrix job**

Check:

- Release candidate R checks: four successful jobs;
- Clean complete installation: three successful jobs;
- Format and encoding matrix: four successful jobs;
- Release coverage gate: successful;
- Repository checks: successful;
- Performance and memory gate: successful.

- [ ] **Step 3: Apply the failure loop if necessary**

For any failure:

1. fetch the exact job and failure step;
2. reproduce locally;
3. write a failing regression test;
4. implement one root-cause fix;
5. run focused and full verification;
6. commit and push;
7. restart monitoring.

Completion requires zero failed, queued, or in-progress checks.

---

### Task 6: Rebuild the final package from the green commit

**Files:**
- Final: `artifacts/cran/DCC_1.2.0.tar.gz`
- Final: `artifacts/cran/DCC_1.2.0.sha256`
- Final: `artifacts/cran/release-metadata.json`

**Interfaces:**
- Consumes: the exact all-green Git commit.
- Produces: the final CRAN upload artifact tied to commit and checksum.

- [ ] **Step 1: Confirm commit identity**

```sh
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
```

Expected: local and remote commit hashes are identical; only known generated
release artifacts are untracked.

- [ ] **Step 2: Rebuild and recheck**

```sh
R CMD build --no-manual .
R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz
```

Expected: the same clean CRAN result as Task 4.

- [ ] **Step 3: Copy and hash the final archive**

```sh
mkdir -p artifacts/cran
cp DCC_1.2.0.tar.gz artifacts/cran/DCC_1.2.0.tar.gz
shasum -a 256 artifacts/cran/DCC_1.2.0.tar.gz \
  > artifacts/cran/DCC_1.2.0.sha256
```

Expected: the archive and checksum file both exist under `artifacts/cran/`.

- [ ] **Step 4: Write release metadata**

Run:

```sh
Rscript -e 'archive <- "artifacts/cran/DCC_1.2.0.tar.gz";
commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE);
sha <- unname(as.character(tools::sha256sum(archive)));
value <- list(package = "DCC", version = "1.2.0", commit = commit,
archive = basename(archive), sha256 = sha, github_checks = "pass",
r_cmd_check = list(errors = 0L, warnings = 0L,
allowed_notes = list("cran_new_submission"), actionable_notes = list()));
jsonlite::write_json(value, "artifacts/cran/release-metadata.json",
auto_unbox = TRUE, pretty = TRUE)'
```

Expected: metadata contains the actual green commit and actual archive hash.

- [ ] **Step 5: Verify final deliverables**

```sh
shasum -a 256 -c artifacts/cran/DCC_1.2.0.sha256
Rscript tools/classify-r-check.R \
  --log=DCC.Rcheck \
  --output=artifacts/cran/r-check-final.json
```

Expected: checksum verification and check classification both pass.
