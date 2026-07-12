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
