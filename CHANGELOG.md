# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Capability contract 1.2, finding codes and detector identity, terminal
  dispositions, complete stage provenance, and disposition/provenance schemas.
- A canonical import contract with variable dictionaries, cell-level missing
  states, strict type conversion, source/import-spec hashes, and public
  `dcc_import()`, `dcc_dictionary()`, and `dcc_missing_states()` interfaces.
- One adapter registry for text, structured text, spreadsheets, statistical
  files, columnar files, RDS, and bounded compressed sources; capabilities and
  backend health diagnostics use this registry as their source of truth.
- A strict versioned Excel/JSON project plan with a protected bilingual
  template, cell-addressed validation, safe staff preflight, plan-based
  one-command runs, bilingual help, and synthetic examples for staff,
  statistical programmers, and AI agents.

### Fixed

- Invalid numerics are no longer silently dropped; YAML and chunked detection
  use declared rule IDs; all-missing score totals remain missing; custom scores
  are length/type checked; run output is atomically published and manifest
  failures are fatal.

## [1.1.0] - 2026-07-12

Additive-contracts release (Phases 3, 4, and 5 of the engineering plan):
machine-readable capabilities and JSON Schemas for AI callers, plus a
one-command workflow, an Excel configuration, a declarative codebook, and skip
logic for survey staff. All changes are additive; no 1.0.x call changes shape.

### Added

- Add `dcc_run()`: a one-command `preview`/`execute`/`verify`/`rerun` workflow
  driven by a `dcc_config()`, writing a fixed output layout
  (`cleaned-data.csv`, `findings.xlsx`, `audit-log.csv`,
  `management-report.html`, `audit-report.html`, `manifest.yaml`,
  `run-summary.txt`). Preview is the default and the raw input is never
  modified in any mode. Add `dcc_run_files()` and `dcc_config()` /
  `dcc_validate_config()`.
- Add `dcc_read_config()` and `dcc_write_config_template()`: an Excel
  cleaning-plan workbook that converts to a `dcc_config()`, so survey staff
  configure a run without writing YAML.
- Add `dcc_apply_codebook()` and `dcc_codebook_changes()`: a declarative
  codebook (rename, recode, missing declaration, type, labels, roles) with a
  `dry_run` preview that shares one planner with the apply path. Raw input is
  never overwritten.
- Add a declarative `skip_logic` rule type and a structural-missingness map:
  `detect_missing_items()` gains a `structural` argument so a legitimately
  skipped item is excluded from the missing proportion (default behaviour
  unchanged). Chunked detection rejects `skip_logic` with `dcc_chunk_error`.
- Add structured validators `dcc_validate_rules()`, `dcc_validate_data()`, and
  `dcc_doctor()` returning a `dcc_validation` report (`code`, `severity`,
  `field`, affected `rows`, `fix`), plus `dcc_validation_errors()`.
- Add `dcc_capabilities()`: a versioned, deterministic capability document
  (`contract_version`, `package_version`, `features` with status and `since`,
  `rule_types`, `action_types`, `formats`, `unsupported`). `dcc_execute()` and
  `dcc_read()` now build their action-name and format sets from the same
  internal source of truth, so the document cannot drift from the engine.
- Add `dcc_schema()` and published draft-07 JSON Schemas under `inst/schemas/`
  for a finding, an audit-log row, a rule file, an action map, and a manifest.
- Add public accessors `dcc_unhandled()`, `dcc_item_map()`, and
  `dcc_mapping_findings()` so callers never read hidden object attributes.
- Add `AI_USAGE.md` documenting the safe validate-before-execute flow, the
  approved public functions, complete rule/action examples, unsupported
  operations, success checks, and raw-data safety for AI systems.

## [1.0.1] - 2026-07-12

Audit-correctness and format-reliability release. All changes are additive to
the public `dcc_findings` and audit-log schemas; no valid public call changes
shape.

### Added

- Add a deterministic `finding_id` to every finding (run + check + record +
  variable + occurrence), assigned by `dcc_findings()`, `bind_findings()`,
  `dcc_detect()`, and `dcc_detect_chunked()`. The detect run prefix is derived
  from the rule and source-file hashes, so identical data and rules reproduce
  identical identities.
- Add a `finding_id` column to the audit log (its new first column), copied
  exactly from the finding that produced each change.
- Add `result$unhandled`: the `dcc_findings` subset with no explicit action.
- Add a `status` column to `dcc_reconcile()` output (`changed`, `excluded`,
  `flagged`, `unhandled`).
- Add `dcc_detect_chunked(sep = NULL)` separator inference (tab for `.tsv`,
  comma otherwise) and data.table-compatible first-chunk type locking.
- Add `tests/testthat/test-format-matrix.R` certifying CSV, TSV, JSON, Excel,
  SPSS, Stata, SAS, Parquet, and Feather input, plus Arrow multi-batch
  Parquet/Feather parity in `test-chunked.R`. Add `writexl` to `Suggests` and
  to the R CMD check dependency set.

### Fixed

- `dcc_execute()` now validates the complete plan before touching data:
  unknown action IDs, unmapped recodes, missing or duplicated record IDs, and
  cell-level actions on group-level findings raise `dcc_execute_error` instead
  of silently degrading. A bad plan can no longer leave a half-applied dataset.
- `dcc_reconcile()` joins audit rows to findings on the exact `finding_id`
  instead of a loose `record_id + check_id` match, so a change can never be
  attributed to the wrong finding; an orphan audit row raises
  `dcc_reconcile_error`.
- Chunked CSV/TSV runs no longer warn on exact chunk multiples, later
  all-`NA` chunks, quoted delimiters, embedded newlines, or latin1 input.

### Changed

- Findings without an explicit action are returned unhandled rather than
  auto-flagged; `dcc_execute(default =)` is retained for call compatibility but
  no longer auto-dispositions.
- `dcc_reconcile()` drops the `unreconciled_changes` attribute in favour of the
  per-finding terminal `status`.

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

### Fixed

- Make `dcc_execute()` linear in the number of findings. Two hidden
  quadratic paths made large runs pathological (about 1040s for ~210k
  changes over 1e6 rows): the audit log grew a list with
  `list[[length + 1]] <-`, and each finding resolved its rows with a
  `row_of[[record_id]]` linear name scan. The audit and exclusion
  buffers are now pre-sized, record ids are hashed to row positions
  once via `match()`, and the per-run timestamp/version/hash are
  stamped once instead of per change. Cleaned data and audit output are
  unchanged.

### Changed

- Rewrite `README.md` as the DCC package README (overview, install,
  end-to-end example, workflow, documentation links) in place of the
  repository-template placeholder.
- Set the license to `GPL (>= 2)`, include the GPL version 2 text, and document
  dependency copyright boundaries in `inst/COPYRIGHTS`. Copyright is held by
  WEIAN DATA TECH (Beijing) Co., Ltd.
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
