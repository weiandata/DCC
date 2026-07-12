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
* Rewrote the README around the package, licensed the project under MIT
  (copyright WeianData Technology (Beijing) Co., Ltd.), and recorded
  authorship, copyright, and funding in `DESCRIPTION`.

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
