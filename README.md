# DCC — Data Cleaning Center

Rule-driven, auditable cleaning of survey and assessment response data,
implementing the WeianData **Detect → Execute → Report** workflow.

Status: Active · Owner: WeianData Engineering · License: MIT

## Overview

DCC treats data cleaning as an auditable pipeline rather than a pile of ad-hoc
edits. Raw data is immutable; every correction is driven by a declarative,
versioned rule and recorded at the cell level, so any value in the cleaned
dataset can be traced back to the finding and rule that changed it, and a whole
run can be reproduced from a manifest.

It is built for survey and educational-assessment data: multi-format and
multi-encoding input, response-quality detectors, answer-key scoring, multi-form
item-bank alignment, and self-contained HTML reports.

## Installation

```r
# install.packages("remotes")
remotes::install_github("weiandata/DCC")
```

Only `data.table` and `stringi` are hard dependencies. Format- and
feature-specific packages (`readxl`, `haven`, `arrow`, `jsonlite`, `yaml`) are
suggested and loaded on demand.

## Quick start

```r
library(DCC)

# 1. A small response file and a declarative rule set
csv <- tempfile(fileext = ".csv")
writeLines(c("sid,score", "S1,90", "S2,150", "S3,70"), csv)

rules_file <- tempfile(fileext = ".yaml")
writeLines(c(
  "checks:",
  "  - id: R001",
  "    type: range",
  "    variable: score",
  "    min: 0",
  "    max: 100"
), rules_file)

# 2. Read -> Detect -> Execute
x     <- dcc_read(csv)
rules <- dcc_rules(rules_file)
found <- dcc_detect(x, rules, id_var = "sid")            # S2 is out of range
res   <- dcc_execute(x, found,
                     actions = list(R001 = "set_na"),    # blank the bad cell
                     id_var = "sid")

dcc_cleaned(res)      # the corrected data
dcc_audit_log(res)    # one row per change, with old/new value and rule

# 3. Report, trace, reproduce
dcc_report(res, tempfile(fileext = ".html"))  # dual-layer HTML report
dcc_trace(res, "S2", "score")                 # full history of one cell
dcc_rerun(dcc_manifest(res))$reproduced       # TRUE: byte-identical rerun
```

See `vignette("dcc-pipeline", package = "DCC")` for the full walkthrough.

## The workflow

**Detect.** `dcc_read()` loads CSV/TSV, Excel, SPSS/Stata/SAS, Parquet/Feather,
and rectangular JSON with encoding auto-detection. `dcc_detect()` evaluates a
versioned `dcc_rules()` set: range/set/expression checks plus five
response-quality detectors — missing items, straight-lining, response time,
trap items, and score anomalies — producing a structured `dcc_findings` object.

**Execute.** `dcc_execute()` applies declarative actions (`exclude`, `set_na`,
`recode`, `flag`) mapped to rule IDs. The whole plan is validated before any
data changes — unknown action IDs, unmapped recodes, and missing or duplicated
record IDs are errors, and findings without an explicit action are returned
*unhandled* rather than silently dispositioned. Input data is never mutated;
every change is written to a cell-level audit log that carries the exact
`finding_id` it came from, with old/new value, triggering rule, method,
timestamp, and rule/key hashes. `dcc_score()` and `dcc_map_forms()` handle
answer-key scoring and multi-form item-bank alignment.

**Report.** `dcc_report()` produces a self-contained, dependency-free HTML
report with a management summary and an audit layer that reconciles findings
against changes on the exact `finding_id`, assigning each finding one terminal
status. `dcc_trace()` gives cell-level lineage; `dcc_manifest()` / `dcc_rerun()`
provide one-command, hash-verified reproduction.

**Scale.** Core work runs on `data.table` for million-row in-memory workloads.
`dcc_detect_chunked()` streams larger-than-memory files with an adaptive backend
(`data.table` for delimited text, `arrow` for Parquet/Feather), with findings
identical to the in-memory path.

**Contracts.** `dcc_capabilities()` returns a versioned, machine-readable list
of every Stable, Experimental, and Planned feature, rule type, action type, and
input format. `dcc_schema()` returns published JSON Schemas for findings, audit
logs, rule files, action maps, and manifests, so programmatic and AI callers
work against a stable contract.

## Documentation

- `vignette("dcc-pipeline")` — end-to-end walkthrough
- [AI usage guide](AI_USAGE.md) — the safe validate-before-execute flow for
  general-purpose AI callers
- [Remediation engineering plan](ENGINEERING_PLAN.md) — approved baseline for
  subsequent development and release acceptance
- [Design document](docs/design.md)
- [Development notes](docs/development-notes.md)
- [CHANGELOG](CHANGELOG.md) / [NEWS](NEWS.md)
- [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md)

## Data and security

All example and test data are synthetic. Do not commit credentials, secrets,
personal information, or unapproved datasets; follow [SECURITY.md](SECURITY.md)
for private vulnerability reporting.

## License

Released under the [MIT License](LICENSE.md).
Copyright © 2026 WeianData Technology (Beijing) Co., Ltd. (惟数据科技(北京)有限公司).
