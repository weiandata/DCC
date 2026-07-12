# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-12

First stable, CRAN-targeted release. The public API (exported `dcc_*`
functions, the `dcc_findings` and audit-log schemas) is now considered
stable; breaking changes to either schema will be major releases.

### Added

- Add `vignettes/dcc-pipeline.Rmd`: an end-to-end walkthrough of the
  Detect -> Execute -> Report workflow (`VignetteBuilder: knitr`).
- Add runnable `\examples` to `dcc_detect_chunked()`, `dcc_manifest()`,
  and `dcc_rerun()`, completing example coverage for every exported
  function.
- Add `NEWS.md` (package-level release notes) and `URL`/`BugReports`
  links in `DESCRIPTION`.

### Changed

- Rewrite `README.md` as the DCC package README (overview, install,
  end-to-end example, workflow, documentation links) in place of the
  repository-template placeholder.
- Set the license to `MIT`: add the `MIT + file LICENSE` declaration,
  the two-line `LICENSE`, and the full-text `LICENSE.md`. Copyright is
  held by WeianData Technology (Beijing) Co., Ltd.
- Record authorship and ownership in `DESCRIPTION` via `Authors@R`:
  Kunxiang Ma as author/maintainer, the company as copyright holder
  (`cph`) and funder (`fnd`).

## [0.5.0] - 2026-07-12

First release of the DCC package: the complete Detect-Execute-Report
workflow with an adaptive larger-than-memory backend.

### Added

- Add an adaptive backend to `dcc_detect_chunked()`: a `backend`
  argument (`"auto"`/`"csv"`/`"arrow"`) selects between the delimited
  (fread) path and a new Arrow path that streams Parquet/Feather files
  as record batches. `"auto"` picks the backend from the file
  extension; the Arrow path takes types from the file schema and is
  encoding-agnostic. Findings are identical across backends and to
  in-memory `dcc_detect()`, and the chosen backend is recorded as a
  `backend` attribute. The `csv` backend gains an `encoding` override
  for inputs where charset auto-detection misfires (e.g. pure-ASCII).
- Add `dcc_detect_chunked()`: larger-than-memory detection for
  delimited files. Record-local checks run chunk by chunk with results
  identical to in-memory `dcc_detect()`; cross-record checks
  (`score_anomaly`, median-relative response time) are rejected with
  typed errors; column types are locked from the first chunk.
- Add `benchmarks/benchmark.R` and the `R-benchmark` workflow: CI
  regression gate timing read/detect/execute at 1e4 and 1e6 rows
  (larger scales via `DCC_BENCH_ROWS`), with per-stage budgets and CSV
  artifacts, plus informational `chunked_csv`/`chunked_arrow` streaming
  stages.

- Add `dcc_report()`: dual-layer self-contained HTML reports (no
  pandoc dependency) -- management summary (findings by quality
  dimension and severity, change volumes, provenance, hashes) and
  audit layer (reconciliation table plus capped cell-level change
  log).
- Add `dcc_reconcile()`: two-way closed-loop verification -- unhandled
  findings are listed and changes without a matching finding are
  counted as `unreconciled_changes`.
- Add `dcc_trace()`: cell-level lineage -- all findings and logged
  changes for one record or one cell of the cleaned data.
- Add `dcc_manifest()` / `dcc_rerun()`: manifest-based one-command
  reproduction. The manifest captures input and rule hashes, actions
  and output content hashes; rerun re-executes read -> detect ->
  execute, refusing (typed errors) when the raw data or rules changed,
  and verifies the cleaned data and audit log byte-identically
  (timestamps excluded).
- Add `dcc_execute()`: the Execute stage. Declarative actions
  (`exclude`, `set_na`, `recode`, `flag`) mapped to `check_id`s;
  unmapped findings are flagged, never dropped; input data is
  immutable and every change is logged at cell level (old/new value,
  triggering check, method, timestamp, versions, rule/key hashes).
- Add `dcc_audit_log()` / `dcc_cleaned()` accessors and
  `dcc_export_log()` (Parquet default, CSV for auditors).
- Add `dcc_score()`: answer-key scoring (single choice,
  multiple-select all-or-nothing and partial credit), omit policies
  `zero`/`na`, pluggable `scoring_fn` extension point, key-file hash
  recorded in provenance.
- Add `dcc_map_forms()`: multi-form to master item bank alignment with
  structural `NA` for not-administered items (IRTC
  concurrent-calibration layout), `is_anchor` carried through, and
  mapping problems emitted as findings.
- Add the `dcc_findings` violation-list object: the structured
  interface between the Detect and Execute stages (record x check x
  evidence x severity x quality dimension).
- Add the five v1-core response-quality detectors: `detect_missing_items()`,
  `detect_straightlining()` (vectorized longstring),
  `detect_response_time()` (absolute and median-relative cuts),
  `detect_trap_items()`, and `detect_score_anomaly()` (within-group
  IQR/z-score outliers plus group-mean shift findings).
- Add the declarative YAML rule engine subset: `dcc_rules()` (rule file
  with MD5 hash for the audit trail) and `dcc_detect()` (pure,
  deterministic evaluation of `range`/`set`/`expr` checks and detector
  configs; `expr` runs in a restricted no-I/O environment; `detect`
  provenance appended when run on a `dcc_data`).
- Add the DCC R package skeleton (`DESCRIPTION`, `NAMESPACE`, `R/`,
  `tests/`) targeting the Detect-Execute-Report design (`docs/design.md`).
- Add `dcc_read()`: multi-format input layer (CSV/TSV, Excel, SPSS,
  Stata, SAS, Parquet, Feather, rectangular JSON) with encoding
  auto-detection (UTF-8, GB18030/GBK, BIG5, latin1) and explicit override.
- Add the `dcc_data` container with metadata and an append-only
  provenance chain.
- Add `dcc_l0_diagnose()`: level-0 structural diagnostics producing a
  machine-readable read report (findings share the detect-stage shape).
- Add testthat suite including an encoding round-trip matrix and typed
  error checks.
- Add R CMD check workflow for continuous integration.

### Changed

- `dcc_execute()` hot loop now uses vector indexing instead of per-row
  `data.table` subsetting, keeping execution cheap when findings run
  into the hundreds of thousands.
- `response_time` rules distinguish an explicitly null
  `min_median_ratio` (`~`, disables the median-relative cut) from an
  absent key (keeps the 1/3 default).

## [Template baseline] - 2026-07-10

The WeianData repository template this package was seeded from (its own
1.0.0), kept here for provenance; DCC package versions are tracked in
the sections above and in `NEWS.md`.

### Added

- Establish the language-independent WeianData repository template.
- Add governance, contribution, security, ownership, and versioning documents.
- Add issue and pull request templates.
- Add Markdown and link validation workflow.
- Add documentation, examples, and scripts guidance.
