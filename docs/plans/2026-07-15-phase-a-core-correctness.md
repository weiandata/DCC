# Phase A Core Correctness Implementation Plan

**Status:** Complete (2026-07-15). All exit criteria passed on
`codex/dcc-phase-a`; full tests and `R CMD check --no-manual` completed with
`Status: OK`.

> **Execution:** Complete the checked tasks in order, with the stated red/green
> verification and review checkpoint before each commit.

**Goal:** Close the correctness and contract defects that block every later
three-audience input and reporting phase.

**Architecture:** Keep the existing Detect -> Execute -> Report engine, add
machine-readable finding codes and detector metadata, normalize YAML rule IDs,
make scoring and execution failure semantics exact, and make run publication
atomic. Later phases build only on these corrected public contracts.

**Tech Stack:** R >= 4.1, data.table, testthat edition 3, jsonlite,
jsonvalidate, yaml.

## Global Constraints

- Raw input is never overwritten.
- Preview remains the default; execution is explicit.
- Existing direct `detect_*()` calls keep legacy `Q_*` check IDs.
- YAML rules use their declared IDs; legacy YAML action IDs warn for one
  transition release and are rejected when ambiguous.
- Public schema changes are additive and contract-versioned.
- Every task ends with focused tests and a separate commit.

---

### Task 1: Add finding codes and detector identity

**Files:**
- Modify: `R/findings.R:22`
- Modify: `inst/schemas/finding.schema.json`
- Modify: `tests/testthat/test-findings.R`
- Modify: `man/dcc_findings.Rd`

**Interfaces:**
- Produces: `dcc_findings(..., code = check_id, detector_id = check_id)`.
- Preserves: existing columns and call sites; two columns are appended.

- [ ] **Step 1: Write the failing constructor test**

```r
test_that("findings expose stable code and detector identity", {
  f <- dcc_findings("S1", "q1", "R001", "bad",
                    code = "OUT_OF_RANGE", detector_id = "range")
  expect_identical(f$code, "OUT_OF_RANGE")
  expect_identical(f$detector_id, "range")
  legacy <- dcc_findings("S1", "q1", "Q_TRAP_ITEMS", "bad")
  expect_identical(legacy$code, "Q_TRAP_ITEMS")
  expect_identical(legacy$detector_id, "Q_TRAP_ITEMS")
})
```

- [ ] **Step 2: Run the focused test and confirm red**

Run: `Rscript -e 'devtools::test(filter="findings", reporter="summary")'`

Expected: failure because `code` and `detector_id` are unused arguments.

- [ ] **Step 3: Extend the constructor without reordering old columns**

```r
dcc_findings <- function(record_id = character(), variable = NA_character_,
                         check_id = character(), evidence = character(),
                         severity = "warn", dimension = NA_character_,
                         code = check_id, detector_id = check_id) {
  n <- max(length(record_id), length(check_id), length(evidence))
  dt <- data.table::data.table(
    finding_id = rep_len(NA_character_, n),
    record_id = rep_len(as.character(record_id), n),
    variable = rep_len(as.character(variable), n),
    check_id = rep_len(as.character(check_id), n),
    evidence = rep_len(as.character(evidence), n),
    severity = rep_len(as.character(severity), n),
    dimension = rep_len(as.character(dimension), n),
    code = rep_len(as.character(code), n),
    detector_id = rep_len(as.character(detector_id), n)
  )
  data.table::setattr(dt, "class", c("dcc_findings", class(dt)))
  dt[]
}
```

Retain the constructor's existing length and required-field validations around
this table construction.

- [ ] **Step 4: Update schema and documentation**

Add `code` and `detector_id` as required strings in
`finding.schema.json`; update the Rd value section and schema test expected
columns.

- [ ] **Step 5: Run focused tests and commit**

Run: `Rscript -e 'devtools::test(filter="findings|schema", reporter="summary")'`

Expected: all focused tests pass.

```bash
git add R/findings.R inst/schemas/finding.schema.json \
  tests/testthat/test-findings.R tests/testthat/test-schema.R \
  man/dcc_findings.Rd
git commit -m "feat(findings): add stable codes and detector identity"
```

### Task 2: Detect invalid numeric input instead of dropping it

**Files:**
- Modify: `R/rules.R:228`
- Modify: `tests/testthat/test-rules.R`
- Modify: `man/dcc_detect.Rd`

**Interfaces:**
- Produces: `code = "INVALID_NUMERIC"` for non-missing values that cannot be
  converted; `code = "OUT_OF_RANGE"` for numeric range violations.

- [ ] **Step 1: Write failing invalid-numeric coverage**

```r
test_that("range rules report invalid numeric source values", {
  rs <- dcc_rules(write_rules(paste(
    "checks:", "  - id: R001", "    type: range",
    "    variable: score", "    min: 0", "    max: 100", sep = "\n")))
  x <- data.frame(sid = c("S1", "S2", "S3"),
                  score = c("abc", "150", NA_character_))
  expect_warning(f <- dcc_detect(x, rs, id_var = "sid"), NA)
  expect_identical(f$record_id, c("S1", "S2"))
  expect_identical(f$code, c("INVALID_NUMERIC", "OUT_OF_RANGE"))
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="rules", reporter="summary")'`

Expected: `S1` is absent.

- [ ] **Step 3: Replace silent coercion with explicit masks**

```r
raw <- r$dt[[v]]
raw_missing <- is.na(raw)
vals <- suppressWarnings(as.numeric(as.character(raw)))
invalid <- !raw_missing & is.na(vals)
outside <- rep.int(FALSE, length(vals))
if (!is.null(ch$min)) outside <- outside | (!is.na(vals) & vals < ch$min)
if (!is.null(ch$max)) outside <- outside | (!is.na(vals) & vals > ch$max)
hit <- which(invalid | outside)
dcc_findings(
  record_id = r$ids[hit], variable = v, check_id = as.character(ch$id),
  evidence = ifelse(invalid[hit],
                    sprintf("value '%s' is not numeric", raw[hit]),
                    sprintf("value %s outside range [%s, %s]", vals[hit],
                            ch$min %||% -Inf, ch$max %||% Inf)),
  severity = severity,
  dimension = if (is.na(dimension)) "validity" else dimension,
  code = ifelse(invalid[hit], "INVALID_NUMERIC", "OUT_OF_RANGE"),
  detector_id = "range"
)
```

- [ ] **Step 4: Run tests and commit**

Run: `Rscript -e 'devtools::test(filter="rules|format-matrix", reporter="summary")'`

```bash
git add R/rules.R tests/testthat/test-rules.R man/dcc_detect.Rd
git commit -m "fix(rules): report invalid numeric values"
```

### Task 3: Make YAML rule IDs public and preserve legacy aliases

**Files:**
- Modify: `R/rules.R:81`
- Modify: `R/run.R:84`
- Modify: `R/config.R:199`
- Modify: `R/execute.R:45`
- Modify: `tests/testthat/test-rules.R`
- Modify: `tests/testthat/test-config.R`
- Modify: `tests/testthat/test-execute.R`
- Modify: `AI_USAGE.md`

**Interfaces:**
- Produces: YAML findings with `check_id = ch$id` and
  `detector_id = Q_*`; direct detector calls are unchanged.
- Produces: `normalize_legacy_action_ids(findings, actions)`.

- [ ] **Step 1: Write declared-ID and ambiguity tests**

```r
test_that("YAML detector findings use declared IDs", {
  rs <- dcc_rules(write_rules(paste(
    "checks:", "  - id: M001", "    type: missing_items",
    "    items: [q1, q2]", "    max_prop: 0.4", sep = "\n")))
  f <- dcc_detect(data.frame(sid = "S1", q1 = NA, q2 = 1), rs, "sid")
  expect_identical(f$check_id, "M001")
  expect_identical(f$detector_id, "Q_MISSING_ITEMS")
})

test_that("ambiguous legacy detector action IDs are rejected", {
  f <- dcc_findings(c("S1", "S2"), c("q1", "q1"), c("M1", "M2"),
                    c("e1", "e2"), detector_id = "Q_MISSING_ITEMS")
  expect_error(dcc_execute(data.frame(sid = c("S1", "S2"), q1 = 1), f,
                           list(Q_MISSING_ITEMS = "flag"), "sid"),
               class = "dcc_execute_error")
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="rules|config|execute", reporter="summary")'`

- [ ] **Step 3: Normalize findings at the YAML boundary**

After `eval_check()` returns inside `dcc_detect()`:

```r
out <- eval_check(x, ch, id_var = id_var, structural = structural)
if (nrow(out)) {
  out[, detector_id := check_id]
  out[, check_id := as.character(ch$id)]
}
out
```

Change `produced_check_ids()` and `cfg_produced_id()` to return declared IDs.

- [ ] **Step 4: Add one-release legacy action normalization**

```r
normalize_legacy_action_ids <- function(findings, actions) {
  legacy <- intersect(names(actions), unique(findings$detector_id))
  for (old in legacy) {
    ids <- unique(findings[detector_id == old, check_id])
    if (length(ids) != 1L || ids %in% names(actions)) {
      dcc_abort("Legacy action ID '", old, "' is ambiguous; use declared rule IDs.",
                class = "dcc_execute_error")
    }
    warning("Action ID '", old, "' is deprecated; use '", ids, "'.",
            call. = FALSE)
    names(actions)[names(actions) == old] <- ids
  }
  actions
}
```

Call it before `validate_execution_plan()`.

- [ ] **Step 5: Update examples, run tests, and commit**

Run: `Rscript -e 'devtools::test(filter="rules|config|execute|run", reporter="summary")'`

```bash
git add R/rules.R R/run.R R/config.R R/execute.R \
  tests/testthat/test-rules.R tests/testthat/test-config.R \
  tests/testthat/test-execute.R AI_USAGE.md
git commit -m "fix(rules): use declared YAML detector IDs"
```

### Task 4: Correct NA totals and validate custom scoring

**Files:**
- Modify: `R/score.R:65`
- Modify: `tests/testthat/test-score.R`
- Modify: `man/dcc_score.Rd`

**Interfaces:**
- Guarantees: all-NA scored rows remain `NA` for `omit_policy = "na"`.
- Guarantees: custom scoring output is numeric and exactly `nrow(data)` long.

- [ ] **Step 1: Write failing scoring tests**

```r
test_that("all structural missing scores have NA total", {
  x <- data.frame(q1 = NA, q2 = NA)
  key <- data.frame(item = c("q1", "q2"), key = c(1, 1))
  out <- as.data.frame(dcc_score(x, key, omit_policy = "na"))
  expect_true(is.na(out$total_score))
})

test_that("custom scoring has an exact numeric contract", {
  expect_error(dcc_score(score_df(), score_key(),
                         scoring_fn = function(x, k) "bad"),
               class = "dcc_score_error")
  expect_error(dcc_score(score_df(), score_key(),
                         scoring_fn = function(x, k) 1),
               class = "dcc_score_error")
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="score", reporter="summary")'`

- [ ] **Step 3: Enforce scoring output and total semantics**

```r
raw_score <- scoring_fn(resp, krow)
if (!is.numeric(raw_score) || length(raw_score) != length(resp)) {
  dcc_abort("`scoring_fn` must return a numeric vector of length ",
            length(resp), ".", class = "dcc_score_error")
}
s <- as.numeric(raw_score)
```

Replace total construction with:

```r
score_dt <- dt[, score_cols, with = FALSE]
total <- rowSums(score_dt, na.rm = TRUE)
if (omit_policy == "na") total[rowSums(!is.na(score_dt)) == 0L] <- NA_real_
data.table::set(dt, j = "total_score", value = total)
```

- [ ] **Step 4: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="score|map-forms", reporter="summary")'
git add R/score.R tests/testthat/test-score.R man/dcc_score.Rd
git commit -m "fix(score): preserve all-missing total semantics"
```

### Task 5: Add explicit disposition and stage provenance contracts

**Files:**
- Create: `R/dispositions.R`
- Modify: `R/execute.R`
- Modify: `R/report.R:148`
- Modify: `R/dcc_data.R:45`
- Create: `tests/testthat/test-dispositions.R`
- Modify: `tests/testthat/test-dcc-data.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_dispositions.Rd`

**Interfaces:**
- Produces: `dcc_dispositions(result)` with one row per finding and status in
  `changed/excluded/flagged/skipped/failed/unhandled`.
- Produces: provenance columns `started_at`, `ended_at`, `outcome`, `hashes`,
  and `counts`.

- [ ] **Step 1: Write disposition and provenance tests**

```r
test_that("every finding has one terminal disposition", {
  res <- execute_fixture_result()
  d <- dcc_dispositions(res)
  expect_identical(sort(d$finding_id), sort(res$findings$finding_id))
  expect_false(anyDuplicated(d$finding_id))
  expect_true(all(d$status %in% c("changed", "excluded", "flagged",
                                  "skipped", "failed", "unhandled")))
})

test_that("provenance records stage outcome and boundaries", {
  rec <- new_provenance_record("detect", started_at = "a", ended_at = "b",
                               outcome = "success", hashes = list(rules = "h"),
                               counts = list(findings = 2L))
  expect_named(rec, c("stage", "started_at", "ended_at", "outcome",
                      "dcc_version", "hashes", "counts", "details"))
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="dispositions|dcc-data", reporter="summary")'`

- [ ] **Step 3: Add the disposition constructor and accessor**

```r
new_dispositions <- function(findings) {
  data.table::data.table(finding_id = findings$finding_id,
                         action = NA_character_, status = "unhandled",
                         message = NA_character_)
}

dcc_dispositions <- function(x) {
  if (!inherits(x, "dcc_result"))
    dcc_abort("`x` must be a dcc_result.", class = "dcc_type_error")
  data.table::copy(x$dispositions)
}
```

During execution, set successful actions to `changed`, `excluded`, or
`flagged`; when an earlier exclude makes a later cell action inapplicable, set
`skipped`; when an action raises after preflight, set `failed`, discard the
working data copy, and attach dispositions to the `dcc_execute_error`.
`dcc_reconcile()` must return this table joined to findings rather than infer
status from audit rows.

- [ ] **Step 4: Replace the provenance record shape**

```r
new_provenance_record <- function(stage, details = list(),
                                  started_at = dcc_timestamp(),
                                  ended_at = dcc_timestamp(),
                                  outcome = "success", hashes = list(),
                                  counts = list()) {
  list(stage = stage, started_at = started_at, ended_at = ended_at,
       outcome = outcome, dcc_version = dcc_version_string(),
       hashes = hashes, counts = counts, details = details)
}
```

Update `dcc_provenance()` to expose these fields and update all stage call
sites with available hashes and counts.

- [ ] **Step 5: Run tests and commit**

Run: `Rscript -e 'devtools::test(filter="dispositions|execute|report|dcc-data", reporter="summary")'`

```bash
git add R/dispositions.R R/execute.R R/report.R R/dcc_data.R \
  tests/testthat/test-dispositions.R tests/testthat/test-dcc-data.R \
  NAMESPACE man/dcc_dispositions.Rd
git commit -m "feat(audit): add terminal dispositions and stage outcomes"
```

### Task 6: Make run output atomic and manifest failure fatal

**Files:**
- Create: `R/run-files.R`
- Modify: `R/run.R:152`
- Modify: `R/rerun.R:18`
- Modify: `tests/testthat/test-run.R`
- Modify: `tests/testthat/test-rerun.R`

**Interfaces:**
- Produces: `new_run_staging(output_dir, run_id)`,
  `publish_run(staging, output_dir, status)`.
- Guarantees: manifest failure cannot return a successful execute run.

- [ ] **Step 1: Write failing atomic-publication tests**

```r
test_that("data-frame execution cannot silently omit a manifest", {
  out <- tempfile("dcc-out")
  expect_error(dcc_run(data.frame(sid = "S1", score = 150), run_config(), out,
                       mode = "execute"), class = "dcc_run_error")
  expect_false(dir.exists(out))
  expect_length(Sys.glob(paste0(out, ".failed-*")), 1L)
})

test_that("successful publication contains a verified manifest", {
  out <- tempfile("dcc-out")
  run <- dcc_run(write_run_csv(), run_config(), out, mode = "execute")
  expect_true(file.exists(file.path(out, "manifest.yaml")))
  expect_true(dcc_rerun(file.path(out, "manifest.yaml"))$reproduced)
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="run|rerun", reporter="summary")'`

- [ ] **Step 3: Add staging and publication helpers**

```r
new_run_staging <- function(output_dir, run_id) {
  path <- paste0(output_dir, ".staging-", run_id)
  if (dir.exists(path)) unlink(path, recursive = TRUE)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

publish_run <- function(staging, output_dir, status, run_id) {
  target <- switch(status, success = output_dir, preview = output_dir,
                   partial_failure = paste0(output_dir, ".partial-", run_id),
                   failed = paste0(output_dir, ".failed-", run_id))
  if (file.exists(target))
    dcc_abort("Output already exists: ", target, class = "dcc_run_error")
  if (!file.rename(staging, target))
    dcc_abort("Could not publish run directory.", class = "dcc_run_error")
  target
}
```

- [ ] **Step 4: Remove manifest suppression and wrap orchestration**

Replace the `tryCatch(dcc_manifest(...), dcc_manifest_error = ...)` block with
a direct `dcc_manifest(res, path = mf)` call. On error, write a minimal
`run.json` and `run-summary.txt` with `status: failed` into staging, publish the
failed diagnostic directory, then rethrow `dcc_run_error`. Only a verified
manifest allows `success` publication.

- [ ] **Step 5: Run full checks and commit**

Run:

```bash
Rscript -e 'devtools::test(reporter="summary")'
R CMD build .
R CMD check --no-manual DCC_*.tar.gz
```

Expected: test suite passes and R CMD check reports `Status: OK`.

```bash
git add R/run-files.R R/run.R R/rerun.R \
  tests/testthat/test-run.R tests/testthat/test-rerun.R
git commit -m "fix(run): publish outputs atomically"
```

### Task 7: Synchronize contracts and release notes

**Files:**
- Modify: `R/capabilities.R`
- Modify: `inst/schemas/*.schema.json`
- Modify: `tests/testthat/test-capabilities.R`
- Modify: `tests/testthat/test-schema.R`
- Modify: `ENGINEERING_PLAN.md`
- Modify: `README.md`
- Modify: `AI_USAGE.md`
- Modify: `NEWS.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Produces: capability contract `1.2` describing finding codes, declared YAML
  IDs, dispositions, and atomic output.

- [ ] **Step 1: Add contract consistency tests**

```r
test_that("stable correctness capabilities match engine contracts", {
  caps <- dcc_capabilities()
  expect_true(all(c("invalid_numeric", "declared_yaml_ids",
                    "terminal_dispositions", "atomic_run_output") %in%
                  caps$features$name[caps$features$status == "Stable"]))
  expect_identical(caps$contract_version, "1.2")
})
```

- [ ] **Step 2: Update schemas and documentation**

Document the six disposition statuses, finding `code` and `detector_id`,
legacy action-ID warning window, scoring semantics, provenance fields, and
failed/partial output directory rules. Remove the contradictory `D001` example
from `AI_USAGE.md`.

- [ ] **Step 3: Validate every schema with positive and negative instances**

Run:

```r
jsonvalidate::json_validate(good_json, schema_path, engine = "ajv")
jsonvalidate::json_validate(bad_json, schema_path, engine = "ajv")
```

Tests must assert `TRUE` for real objects and `FALSE` for malformed objects.

- [ ] **Step 4: Run final gate and commit**

```bash
Rscript -e 'devtools::test(reporter="summary")'
R CMD build .
R CMD check --no-manual DCC_*.tar.gz
git add R/capabilities.R inst/schemas tests/testthat \
  ENGINEERING_PLAN.md README.md AI_USAGE.md NEWS.md CHANGELOG.md
git commit -m "docs: align correctness contracts"
```

## Phase A Exit Criteria

- Every finding carries stable `code` and `detector_id` fields.
- Invalid numeric input, declared YAML action IDs, NA totals, and custom scoring
  have explicit tested semantics.
- Every finding reaches one terminal disposition with complete provenance.
- Run publication is atomic and manifest failures cannot report success.
- Schemas, capabilities, examples, and release notes match the engine contract.
- Full tests and `R CMD check` complete without errors or warnings.
