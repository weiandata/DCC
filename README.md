# DCC — Data Cleaning Center

Rule-driven, auditable cleaning of survey and assessment response data,
implementing the WeianData **Detect → Execute → Report** workflow.

Status: Active · Owner: WEIAN DATA Engineering · License: GPL (>= 2)

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

All formally supported input backends are installed with DCC: delimited and
fixed-width text, JSON/JSONL, XLS/XLSX/XLSB/ODS, SPSS/Stata/SAS/XPT,
Parquet/Feather, and RDS. `dcc_capabilities()$formats` reports each backend's
installed status and limitations; opening a file alone does not make a format
Stable.

## Quick start

For survey staff the shortest safe workflow uses a protected Excel plan and
four simple functions:

```r
library(DCC)
dcc_template("DCC-cleaning-plan.xlsx")
dcc_check("responses.csv", "DCC-cleaning-plan.xlsx", "dcc-check")
dcc_run("responses.csv", plan = "DCC-cleaning-plan.xlsx",
        output_dir = "dcc-preview")                 # safe default
dcc_help("PLAN_COLUMN_TYPE")                        # plain-language fix
```

Only yellow cells are editable. The bilingual template is strict: unknown or
renamed sheets and columns fail with an exact Excel cell address. After review,
run again with a new output directory and `mode = "execute"`. See the
[Chinese](docs/quick-start-zh-CN.md) and [English](docs/quick-start-en.md)
guides and the [synthetic example](examples/strict-excel-project/README.md).

Statistical programmers may use the same `dcc_plan` through
`dcc_read_plan()`/`dcc_validate_plan()`. AI agents can use JSON with
`dcc_schema("plan")`; Excel and JSON validate to the same contract.

### Programmatic pipeline

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

**Detect.** `dcc_read()` remains the compatibility reader with encoding and
type inference. Strict workflows use `dcc_import()` with declared source
columns, canonical names, types, roles, missing codes, worksheet/range, and
encoding. The canonical result exposes `dcc_dictionary()` and
`dcc_missing_states()`. The registry covers CSV/TSV/TXT/FWF, JSON/JSONL,
XLS/XLSX/XLSB/ODS, SPSS/Stata/SAS/XPT, Parquet/Feather, and RDS, including
bounded gzip and explicit-member ZIP input. `dcc_detect()` evaluates a
versioned `dcc_rules()` set: range/set/expression checks plus five
response-quality detectors — missing items, straight-lining, response time,
trap items, and score anomalies — producing a structured `dcc_findings` object.

**Execute.** `dcc_execute()` applies declarative actions (`exclude`, `set_na`,
`recode`, `flag`) mapped to rule IDs. The whole plan is validated before any
data changes — unknown action IDs, unmapped recodes, and missing or duplicated
record IDs are errors, and findings without an explicit action are returned
*unhandled* rather than silently dispositioned. Every finding also has one
terminal disposition available through `dcc_dispositions()` (`changed`,
`excluded`, `flagged`, `skipped`, `failed`, or `unhandled`). Input data is never mutated;
every change is written to a cell-level audit log that carries the exact
`finding_id` it came from, with old/new value, triggering rule, method,
timestamp, and rule/key hashes. `dcc_score()` and `dcc_map_forms()` handle
answer-key scoring and multi-form item-bank alignment.

**Report.** `dcc_report()` produces a self-contained, dependency-free HTML
report with a management summary and an audit layer that reconciles findings
against changes on the exact `finding_id`, assigning each finding one terminal
status and verifies it against the audit log. `dcc_trace()` gives cell-level lineage; `dcc_manifest()` / `dcc_rerun()`
provide one-command, hash-verified reproduction.

**Scale.** Core work runs on `data.table` for million-row in-memory workloads.
`dcc_detect_chunked()` streams larger-than-memory files with an adaptive backend
(`data.table` for delimited text, `arrow` for Parquet/Feather), with findings
identical to the in-memory path.

**Contracts.** `dcc_capabilities()` returns a versioned, machine-readable list
of every Stable, Experimental, and Planned feature, rule type, action type, and
input format, including extensions, backend, semantics, and limitations.
`dcc_doctor(formats = "all")` checks installed backend versions and platform
constraints. `dcc_schema()` returns published JSON Schemas for strict plans,
findings, audit logs, dispositions, provenance, rule files, action maps, and
manifests, so programmatic and AI callers work against a stable contract.

## Documentation

- `vignette("dcc-pipeline")` — end-to-end walkthrough
- [AI usage guide](AI_USAGE.md) — the safe validate-before-execute flow for
  general-purpose AI callers
- [Strict Excel quick start (中文)](docs/quick-start-zh-CN.md) /
  [English](docs/quick-start-en.md)
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

Released under the [GNU General Public License version 2 or later](LICENSE).
Copyright © 2026 WEIAN DATA TECH (Beijing) Co., Ltd.
(惟安数据科技（北京）有限公司). Dependency copyright boundaries are recorded
in [inst/COPYRIGHTS](inst/COPYRIGHTS).
