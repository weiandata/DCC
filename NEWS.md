# DCC 1.2.0 (development)

* Add stable finding `code` and `detector_id`; range checks now report
  `INVALID_NUMERIC` instead of silently coercing invalid values to missing.
* YAML rules use declared IDs publicly while preserving direct detector IDs;
  unambiguous legacy action aliases warn for one transition release.
* Add `dcc_dispositions()` with one terminal state per finding and make
  reconciliation verify those states against audit evidence.
* Add start/end/outcome/hash/count provenance and preserve legacy timestamp
  records.
* Preserve `NA` totals for entirely missing scored rows and validate custom
  scoring return type and length.
* Publish `dcc_run()` outputs atomically; manifest and other failures create a
  failed diagnostic directory and cannot be returned as success.
* Capability contract 1.2 and new disposition/provenance schemas describe the
  additive machine contract.

# DCC 1.1.0

Additive-contracts release: machine-readable capabilities and formal schemas
for AI callers, plus a one-command workflow and structured validators for
survey staff. Every change is additive; no 1.0.x call changes shape.

* `dcc_run()` runs the whole Detect -> Execute -> Report pipeline from a
  `dcc_config()` and writes a fixed output layout (`cleaned-data.csv`,
  `findings.xlsx`, `audit-log.csv`, the two HTML reports, `manifest.yaml`,
  `run-summary.txt`). Preview is the default mode and the raw input file is
  never modified in any mode. `dcc_run_files()` lists what was written.
* `dcc_read_config()` reads an Excel cleaning-plan workbook into a
  `dcc_config()`, so survey staff configure a run in a spreadsheet instead of
  YAML; `dcc_write_config_template()` writes a starter workbook.
* `dcc_apply_codebook()` applies a declarative codebook (rename, recode,
  missing declaration, type, labels, roles) with a `dry_run` preview that
  shares one planner with the apply path, so a change is previewed exactly as
  applied. The raw input is never overwritten.
* A declarative `skip_logic` rule marks skipped items as *not administered* so
  the missing-items detector no longer counts a legitimately skipped item as
  missingness.
* `dcc_config()` bundles rules, actions, an id column, and items.
* `dcc_validate_rules()`, `dcc_validate_data()`, `dcc_validate_config()`, and
  `dcc_doctor()` return a structured `dcc_validation` report (`code`,
  `severity`, `field`, affected `rows`, and a suggested `fix`) and change
  nothing. `dcc_run()` validates before it detects or executes.
* `dcc_capabilities()` returns a versioned, deterministic document of every
  feature (with `Stable`/`Experimental`/`Planned` status and `since`), rule
  type, action type, and input format, plus the operations DCC does not
  support. The action-type and format lists are the same source of truth the
  engine uses, so the document cannot drift from the implementation.
* `dcc_schema()` returns published draft-07 JSON Schemas (installed under
  `inst/schemas/`) for a finding, an audit-log row, a rule file, an action map,
  and a manifest.
* Added public accessors so callers never read hidden attributes:
  `dcc_unhandled()` (a result's unhandled findings), `dcc_item_map()` and
  `dcc_mapping_findings()` (a `dcc_map_forms()` result's item map and mapping
  problems).
* Added `AI_USAGE.md`: the approved public functions and the safe
  capabilities -> validate -> preview -> execute -> reconcile -> export ->
  verify flow for AI systems.

# DCC 1.0.1

Audit-correctness and format-reliability release. Every finding now has a
stable identity that every audit row and reconciliation joins on exactly, and
every supported input format is certified. All changes are additive to the
public schemas; no valid `dcc_*()` call changes shape.

* Every finding carries a deterministic `finding_id` (run + check + record +
  variable + occurrence). `dcc_detect()` and `dcc_detect_chunked()` derive the
  run prefix from the rule and source-file hashes, so the same data and rules
  reproduce the same identities.
* `dcc_execute()` validates the whole plan before any data changes: unknown
  action IDs, unmapped recodes, missing or duplicated record IDs, and
  cell-level actions on group-level findings are now errors instead of silent
  degradations. Each audit row carries the exact `finding_id` it came from.
* Findings without an explicit action are returned as `result$unhandled`
  rather than being silently auto-flagged, so an unhandled finding can never
  be reported as handled. (`default` is retained for call compatibility but no
  longer auto-dispositions.)
* `dcc_reconcile()` joins audit rows to findings on `finding_id` only and
  assigns each finding one terminal `status` (`changed`, `excluded`,
  `flagged`, or `unhandled`); an audit row with no matching finding raises a
  `dcc_reconcile_error`. The loose `record_id + check_id` matching and the
  `unreconciled_changes` attribute are gone.
* `dcc_detect_chunked()` infers the separator from the extension (`sep = NULL`
  gives a tab for `.tsv`, a comma otherwise) and locks first-chunk column
  types via a data.table-compatible `colClasses` map, so chunked runs are
  warning-free on exact chunk multiples, later all-`NA` chunks, quoted
  delimiters, embedded newlines, and latin1 input.
* Certified the full input matrix (CSV, TSV, JSON, Excel, SPSS, Stata, SAS,
  Parquet, Feather) with a format-matrix test suite and Arrow multi-batch
  Parquet/Feather parity against in-memory findings. Added `writexl` to
  `Suggests` and to the CI dependency set.

# DCC 1.0.0

First stable, CRAN-targeted release. The public API -- the exported `dcc_*`
functions and the `dcc_findings` and audit-log schemas -- is now stable;
breaking changes to either schema will be major releases.

* Added an end-to-end vignette, `vignette("dcc-pipeline")`, covering the
  Detect -> Execute -> Report workflow.
* Completed `\examples` coverage for every exported function
  (`dcc_detect_chunked()`, `dcc_manifest()`, `dcc_rerun()`).
* Rewrote the README around the package, licensed the project under GPL (>= 2)
  (copyright WEIAN DATA TECH (Beijing) Co., Ltd.), recorded authorship,
  copyright, and funding in `DESCRIPTION`, and documented external dependency
  copyright boundaries in `inst/COPYRIGHTS`.

# DCC 0.5.0

First package release, covering the full Detect -> Execute -> Report workflow.

* `dcc_read()` multi-format, multi-encoding input layer; the `dcc_data`
  container with a provenance chain; `dcc_l0_diagnose()` structural
  diagnostics.
* `dcc_rules()` / `dcc_detect()` declarative YAML rule engine and the five
  response-quality detectors (missing items, straight-lining, response time,
  trap items, score anomalies), producing the `dcc_findings` object.
* `dcc_execute()` execution engine with a cell-level audit log; `dcc_score()`
  answer-key scoring; `dcc_map_forms()` multi-form item-bank alignment.
* `dcc_report()` dual-layer HTML reports, `dcc_reconcile()` closed-loop
  verification, `dcc_trace()` cell lineage, and `dcc_manifest()` /
  `dcc_rerun()` manifest-based reproduction.
* `dcc_detect_chunked()` larger-than-memory detection with an adaptive
  CSV/Arrow backend, plus CI performance benchmarks.
