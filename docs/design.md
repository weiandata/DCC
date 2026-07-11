# DCC Design Document

Version: 0.1 (draft)

Status: Draft — for internal review

Owner: WeianData Engineering

Date: 2026-07-11

Related: [Research notes (Chinese)](cran-data-cleaning-packages-survey.md)

---

## 1. Purpose

DCC (Data Cleaning Center) is an R package for cleaning survey and
assessment response data. It implements WeianData's signature data-service
workflow — **Precise Detection → Efficient Execution → Auditable
Reporting** — as a reproducible, rule-driven pipeline in which every cell-level
change can be traced back to a detected violation and a versioned rule.

### Audience

Data analysts and psychometricians at WeianData and client organizations,
from small-sample academic surveys to million-record assessment programs.

### Non-goals

- General-purpose tabular ETL (covered by dplyr/data.table).
- Statistical modeling of cleaned data (IRT/CTT estimation is downstream).
- Data collection or survey hosting.

## 2. Design Principles

1. **Raw data is immutable.** Cleaning always produces a new dataset version;
   the original is read-only.
2. **Detection never modifies; execution never detects.** Detection produces a
   structured findings list; execution consumes only that list.
3. **Minimal change.** Automatic corrections modify the fewest values
   necessary (Fellegi–Holt); prefer deductive correction over imputation,
   imputation over deletion.
4. **Rules are declarative, external, and versioned.** Checks, correction
   actions, answer keys, and form-item maps live in files under version
   control, readable by non-programmers.
5. **Every change is logged at cell level** — record, variable, old value,
   new value, triggering rule, method, timestamp, package version.
6. **Closed loop.** A change without a corresponding finding is a pipeline
   violation. Reports must reconcile findings against changes.
7. **One-command reproducibility.** Same raw data + same rule versions =
   identical cleaned data and reports.
8. **Checks are layered** (structure → cell/record → cross-record →
   cross-dataset, after Eurostat validation levels) and results are scored by
   quality dimension (completeness, validity, consistency, accuracy,
   uniqueness).

## 3. Architecture Overview

```text
                +--------------------+
 raw files ---> |  Input layer       |  dcc_read()          L0 structure checks
                +--------------------+
                          |
                          v
                +--------------------+
                |  DETECT            |  dcc_detect()        rules + built-in
                |  (read-only)       |  -> dcc_findings     quality detectors
                +--------------------+
                          |
                          v
                +--------------------+
                |  EXECUTE           |  dcc_execute()       actions on findings
                |  (minimal change)  |  dcc_score()         answer-key scoring
                |                    |  dcc_map_forms()     form-to-bank mapping
                |                    |  -> dcc_result       new data + audit log
                +--------------------+
                          |
                          v
                +--------------------+
                |  REPORT            |  dcc_report()        summary + audit
                |  (auditable)       |  dcc_trace()         cell-level lineage
                +--------------------+
```

All stages operate on a `dcc_data` object (data + metadata + provenance).
Every stage appends to the provenance chain, never rewrites it.

## 4. Input Layer

`dcc_read(path, format = "auto", encoding = "auto", ...)`

- **Formats:** CSV/TSV (`data.table::fread`), Excel (`readxl`),
  SPSS/Stata/SAS (`haven`, preserving value labels and user-defined
  missings), Parquet/Feather (`arrow`), JSON.
- **Encodings:** automatic detection via `stringi::stri_enc_detect()` with
  explicit override; UTF-8, GB18030/GBK, BIG5, and Latin-1 are first-class.
- On read, DCC runs **level-0 structural validation** (row/column counts,
  column types, encoding confidence) and attaches a read report to the
  object. Reading never silently coerces; all coercions are logged.

## 5. Detection (Precise Detection)

### 5.1 Findings object

Detection produces a `dcc_findings` table — the single interface between
detection and execution:

| column | meaning |
|---|---|
| `record_id` | respondent / row identifier |
| `variable` | affected variable(s), NA for record-level checks |
| `check_id` | stable identifier of the rule or detector |
| `evidence` | measured value (e.g., longstring run = 28) |
| `severity` | `info` / `warn` / `fail` |
| `dimension` | quality dimension the check belongs to |

### 5.2 Built-in response-quality detectors (v1 core)

| function | purpose | notes |
|---|---|---|
| `detect_score_anomaly()` | group-wise score distribution anomalies (between-group differences, outlying scores) | grouping variables supplied by user; methods: IQR, z-score, configurable |
| `detect_trap_items()` | flag respondents failing trap / attention-check items | trap definitions supplied as an external key file |
| `detect_response_time()` | flag too-fast or anomalous total / per-item response times | absolute thresholds and distribution-based (e.g., fraction of median) |
| `detect_straightlining()` | excessive identical consecutive options | longstring index (cf. CRAN `careless`), configurable per scale |
| `detect_missing_items()` | excessive item nonresponse per respondent | threshold on missing proportion; distinguishes skip-logic NA from true missing |

### 5.3 Rule engine

`dcc_rules("rules.yaml")` loads declarative checks (range, set membership,
in-record consistency, skip-logic, cross-record). The file format is YAML
with embedded R expression fields for complex logic (see section 14,
decision 1); expressions run in a restricted evaluation environment. Rules
carry `check_id`, level (L0–L3), dimension, severity, and free-text
rationale. Built-in detectors are configured in the same file so the entire
detection pass is one versioned document.

`dcc_detect(data, rules)` evaluates everything and returns `dcc_findings`.
Detection is pure: same data + same rules = same findings.

## 6. Execution (Efficient Execution)

### 6.1 Actions on findings

`dcc_execute(data, findings, actions)` applies declarative actions
(`exclude record`, `set NA`, `recode`, `deductive-correct`, `impute`,
`keep with flag`) mapped to `check_id`s. Records are excluded by flagging
and filtering into the new version — never deleted from provenance.

### 6.2 Post-cleaning functions

- `dcc_score(data, answer_key)` — score cleaned responses against an
  external answer key: single-choice, multiple-choice (all-or-nothing and
  partial credit) in v1; a pluggable `scoring_fn` argument reserves room
  for weighted/rubric/polytomous scoring in v1.x without API breakage.
  Output: item-level correctness/score matrix appended as a new dataset
  version.
- `dcc_map_forms(data, form_item_map)` — align items from multiple test
  forms onto the master item bank via an external form-item mapping table
  (codebook-style: form ID × form position × master item ID × `is_anchor`).
  The anchor flag is carried through to output for downstream equating;
  unmapped items are findings, not silent drops.
- `dcc_apply_codebook(data, codebook)` — batch rename / recode / label from
  a codebook file (cf. Stata `iecodebook`; no mature CRAN equivalent —
  differentiation opportunity).

Answer keys, form-item maps, and codebooks are versioned inputs; their
versions (file hash) are recorded in the audit log.

### 6.2.1 Interface to the downstream IRT engine (IRTC)

The downstream engine is WeianData's `IRTC` package (TAM-derived MML
estimation: `irtc.mml()`, `irtc.mml.2pl()`). Its input contract is:

- `resp` — wide person × item matrix of scored responses (0/1 or 0..K),
  `NA` = missing; multi-form designs are handled as concurrent calibration
  where items not administered on a form are `NA`.
- `pid`, `group`, `pweights` — person identifiers, integer group codes,
  case weights.
- `Q` — optional item × dimension loading matrix.
- `xsi.fixed` — matrix (parameter index, fixed value) used for fixed-anchor
  equating.

DCC therefore provides `dcc_to_irtc(result)` which returns exactly this
shape from a scored, form-mapped dataset:

| element | source in DCC |
|---|---|
| `resp` | `dcc_score()` output pivoted onto master item bank columns (via `dcc_map_forms()`) |
| `pid` / `group` / `pweights` | pass-through columns declared in the codebook |
| `Q` | optional item-dimension columns of the master item table |
| anchor table | `is_anchor` items with reference parameters, ready to build `xsi.fixed` |

Semantics distinction preserved in the export: **not-administered** items
(form design) are structural `NA`; **omitted** items (respondent skipped)
are scored per answer-key policy (e.g., 0 or `NA`) — the two are never
conflated, and the policy used is recorded in the audit log.

### 6.3 Audit log schema

Every executed change appends one row:

`record_id, variable, old_value, new_value, action, check_id, method,
timestamp, dcc_version, ruleset_hash, keyfile_hash`

The log is a machine-readable table (not only a rendered report), stored
alongside the output dataset as Parquet; `dcc_export_log(format = "csv")`
produces plain-file exports for external auditors.

## 7. Reporting (Auditable Reporting)

- `dcc_report(result, audience = c("summary", "audit"))` —
  **summary**: quality-dimension scores, findings counts, change volumes,
  exclusion rates by group; **audit**: full findings-to-changes
  reconciliation, cell-level log, rule versions. HTML/PDF via R Markdown or
  Quarto.
- `dcc_trace(result, record_id, variable)` — reverse lookup: full cleaning
  history of any cell in the final dataset.
- `dcc_rerun(manifest)` — re-execute the whole pipeline from the manifest
  (raw file hashes + rule/key versions) and verify byte-identical output.

## 8. Performance

- **One API, adaptive backend.** Core computation on `data.table`
  (million-row in-memory workloads); optional `arrow`/`duckdb` backend for
  larger-than-memory data via chunked/lazy evaluation. Backend selection is
  automatic with manual override.
- Rule evaluation is vectorized; no per-row interpretation.
- CI benchmarks at 1e4 / 1e6 / 1e7 rows with regression thresholds.

## 9. Dependencies (proposed)

| area | packages |
|---|---|
| core | data.table, stringi |
| input | readr, readxl, haven, arrow, jsonlite |
| labels/missing | labelled (haven classes) |
| reporting | knitr + rmarkdown or quarto |
| suggested | duckdb (big data), careless (cross-validation of detectors), validate (rule interop) |

Keep the hard-dependency set small; heavy packages go to `Suggests`.

## 10. Package Layout

```text
DCC/
├── R/                  # dcc_read, detect_*, dcc_execute, dcc_score, ...
├── inst/extdata/       # synthetic example data, example rules/keys
├── tests/testthat/     # deterministic unit tests, golden-file audit tests
├── vignettes/          # end-to-end pipeline walkthrough
├── data-raw/           # scripts generating synthetic fixtures
└── benchmarks/         # performance benchmark scripts (CI)
```

Exported functions use the `dcc_` prefix; detectors use `detect_`.
All test and example data are synthetic (per repository security policy).

## 11. Testing and Validation

- Deterministic unit tests per detector and action (testthat).
- Golden-file tests: fixed raw data + rules must reproduce identical audit
  logs and reports.
- Property test for the closed loop: every audit-log row joins to exactly
  one finding; findings with terminal actions are fully reconciled.
- Encoding matrix tests (UTF-8 / GB18030 / BIG5 fixtures).
- Benchmarks in CI (section 8).

## 12. Versioning and Compatibility

Semantic Versioning with `v` tags per repository standard. The audit-log
schema and `dcc_findings` schema are public contracts: breaking changes to
either are MAJOR releases with migration notes in `CHANGELOG.md`.

## 13. Roadmap

| milestone | scope |
|---|---|
| v0.1 | input layer + `dcc_data` object + L0 diagnostics |
| v0.2 | five core detectors + findings object + rule engine (subset) |
| v0.3 | execution engine + audit log + `dcc_score` / `dcc_map_forms` |
| v0.4 | reports (summary + audit) + `dcc_trace` + `dcc_rerun` |
| v0.5 | performance backends (arrow/duckdb) + CI benchmarks |
| v1.0 | stable public API, full documentation, CRAN-readiness review |

## 14. Resolved Design Decisions

Decided by product owner, 2026-07-11:

1. **Rule file format: YAML with embedded R expressions.** The rule file is
   declarative YAML (thresholds, detector configuration, metadata); complex
   logic such as skip-chains is expressed in embedded R expression fields.
   Expressions are evaluated in a restricted environment (no I/O, no side
   effects).
2. **Weighted/rubric/polytomous scoring is deferred to v1.x.** v1 ships
   single-choice, multiple-choice (all-or-nothing and partial credit) only.
   `dcc_score()` accepts a pluggable scoring function so the extension lands
   without breaking the API.
3. **Audit log is stored as Parquet**, with `dcc_export_log(format = "csv")`
   for auditors who need plain files. Parquet gives schema-typed,
   compressed storage at tens of millions of log rows.
4. **Form mapping carries an anchor-item flag field** (`is_anchor`) in its
   output from v1. *Updated 2026-07-11:* the downstream engine interface is
   now confirmed (IRTC, TAM-style `resp`/`pid`/`group`/`pweights`/`Q`/
   `xsi.fixed`); DCC ships `dcc_to_irtc()` as the concrete export
   (section 6.2.1) instead of generic equating metadata.
