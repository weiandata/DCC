# DCC Strict Excel Workflow Quick Start

This entry point is for survey staff who do not program or use statistical software. Edit yellow cells only. Do not add remove rename or reorder sheets and columns. DCC rejects structural changes instead of guessing.

## 1. Install and create the template

```r
remotes::install_github("weiandata/DCC", dependencies = TRUE)
library(DCC)
dcc_template("DCC-cleaning-plan.xlsx", language = "en")
```

Formal input backends install with DCC. The protected workbook contains exactly nine sheets: project source columns values missing multiselect rules actions and outputs. Protection has no password and only prevents accidental structural edits.

## 2. Complete the workbook

Declare the source path format and text encoding. On columns declare every source name canonical name type role and required flag. Rule and action parameters are JSON objects; enter `{}` when no parameters are needed. Keep the stable English machine headers.

## 3. Check first

```r
check <- dcc_check(
  "responses.csv",
  "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-check"
)
```

Review `validation.xlsx`, `preview-findings.xlsx`, `staff-report.html`, and `run-summary.txt`. Check mode never executes an action and never writes cleaned data. Use `dcc_help("PLAN_COLUMN_TYPE", language = "en")` for a plain-language fix.

## 4. Preview and execute

```r
preview <- dcc_run(
  "responses.csv",
  plan = "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-preview"
)

result <- dcc_run(
  "responses.csv",
  plan = "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-result",
  mode = "execute"
)
```

Execution writes cleaned data findings audit logs HTML reports a manifest and a summary. PDF is not a fixed output. DCC never overwrites an existing output directory and never changes the raw source file.

## Statistical professionals and AI agents

Professionals can use `dcc_read_plan()`, `dcc_validate_plan()`, `dcc_import()`, and the existing lower-level API. Agents should query `dcc_capabilities()` and `dcc_schema("plan")` first; use JSON or the strict workbook; check and preview before any explicitly authorized execution; and branch on stable codes classes JSON Pointers or Excel cell coordinates rather than parsing prose.

