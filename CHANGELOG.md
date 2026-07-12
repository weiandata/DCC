# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

## [1.0.0] - 2026-07-10

### Added

- Establish the language-independent WeianData repository template.
- Add governance, contribution, security, ownership, and versioning documents.
- Add issue and pull request templates.
- Add Markdown and link validation workflow.
- Add documentation, examples, and scripts guidance.
