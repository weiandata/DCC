# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
