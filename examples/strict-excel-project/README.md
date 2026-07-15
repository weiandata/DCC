# Strict Excel project example

This directory contains synthetic data and equivalent strict plans for two entry styles:

- `DCC-cleaning-plan.xlsx` for survey staff
- `DCC-cleaning-plan.json` for statistical programmers and AI agents

From this directory run:

```r
library(DCC)
dcc_check("responses.csv", "DCC-cleaning-plan.xlsx", "dcc-check")
dcc_run("responses.csv", plan = "DCC-cleaning-plan.xlsx",
        output_dir = "dcc-preview")
```

After reviewing the diagnostics and preview, use a new output directory and
`mode = "execute"`. The strict `输出设置 / Outputs` sheet selects the three
audience bundles:

- `staff/`: bilingual Excel, HTML, and text for survey staff; examples are
  redacted unless `include_sensitive_examples` is explicitly `TRUE`.
- `statistical/`: complete CSV/Parquet tables, methods, provenance, parameters,
  and SHA-256 artifact manifest for statistical programmers.
- `machine/`: deterministic JSON/JSONL, schemas, bounded summary, and manifest
  for AI agents and external systems.

All three derive from one normalized model and therefore expose the same run
ID, totals, reconciliation, and data hashes. PDF is not a fixed output. All
data in this example are synthetic.
