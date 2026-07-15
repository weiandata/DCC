# Phase C Strict Excel Workflow Implementation Plan

> **Execution:** Complete the checked tasks in order, with the stated red/green
> verification and review checkpoint before each commit.

**Goal:** Give non-programming survey staff a strict, friendly Excel project
plan and a four-function R workflow without creating a second cleaning engine.

**Architecture:** A versioned `dcc_plan` is the common object behind Excel and
JSON inputs. The workbook parser validates exact sheets and columns and returns
cell-addressed issues; `dcc_check()` and the additive `dcc_run(plan=)` path
delegate to Phase B import and the existing cleaning engine.

**Tech Stack:** R >= 4.1, openxlsx2 >= 1.28, jsonlite, jsonvalidate,
data.table, testthat.

**Implementation status (2026-07-15): Complete.** The runtime remains free of
`jsonvalidate`; the closed draft-07 plan Schema is tested against serialized
fixtures using the existing `jsonlite` dependency. Full tests, `R CMD build`,
and `R CMD check --no-manual` pass with `Status: OK`.

## Global Constraints

- Phases A and B are complete.
- Workbook structure is strict; no unknown sheet or column is ignored.
- Template user-input cells are editable; structure and machine headers are
  protected but not encrypted.
- Excel and JSON plans validate to the same `dcc_plan` contract.
- Existing `dcc_run(data, config, output_dir, mode)` calls remain valid.
- `dcc_run()` defaults to preview and cannot overwrite an existing output.

---

### Task 1: Define the versioned plan contract

**Files:**
- Create: `R/plan.R`
- Create: `inst/schemas/plan.schema.json`
- Create: `tests/testthat/test-plan.R`
- Modify: `R/schema.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_validate_plan.Rd`

**Interfaces:**
- Produces: `new_dcc_plan(project, source, columns, values, missing,
  multiselect, rules, actions, outputs)`.
- Produces: `dcc_validate_plan(x)` and `dcc_schema("plan")`.

- [x] **Step 1: Write plan-constructor and validation tests**

```r
test_that("dcc_plan has the exact versioned sections", {
  p <- plan_fixture()
  expect_s3_class(p, "dcc_plan")
  expect_identical(names(p), c("project", "source", "columns", "values",
                                "missing", "multiselect", "rules",
                                "actions", "outputs"))
  expect_identical(p$project$template_version, "1.0")
  expect_length(dcc_validation_errors(dcc_validate_plan(p)), 0L)
})

test_that("unknown plan fields fail", {
  p <- plan_fixture()
  p$source$guess_sheet <- TRUE
  expect_true("PLAN_UNKNOWN_FIELD" %in% dcc_validate_plan(p)$code)
})
```

- [x] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="plan", reporter="summary")'`

- [x] **Step 3: Implement the exact-section constructor**

```r
new_dcc_plan <- function(project, source, columns,
                         values = data.frame(), missing = data.frame(),
                         multiselect = data.frame(), rules = data.frame(),
                         actions = data.frame(), outputs = data.frame()) {
  structure(list(project = project, source = source,
                 columns = data.table::as.data.table(columns),
                 values = data.table::as.data.table(values),
                 missing = data.table::as.data.table(missing),
                 multiselect = data.table::as.data.table(multiselect),
                 rules = data.table::as.data.table(rules),
                 actions = data.table::as.data.table(actions),
                 outputs = data.table::as.data.table(outputs)),
            class = "dcc_plan")
}
```

`dcc_validate_plan()` checks exact section names, template version `1.0`,
required columns, enumerations, unique IDs, cross-sheet foreign keys, declared
source format/options, rule/action compatibility, and output policies.

- [x] **Step 4: Publish and validate the schema**

Add `plan` to `dcc_schema()` and assert a serialized fixture validates while a
plan with an unknown property fails under `jsonvalidate` with draft-07.

- [x] **Step 5: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="plan|schema", reporter="summary")'
git add R/plan.R inst/schemas/plan.schema.json tests/testthat/test-plan.R \
  R/schema.R NAMESPACE man/dcc_validate_plan.Rd
git commit -m "feat(plan): add strict project contract"
```

### Task 2: Generate the protected workbook template

**Files:**
- Create: `R/template.R`
- Create: `tools/build-template.R`
- Create: `inst/templates/DCC-cleaning-plan.xlsx`
- Create: `tests/testthat/test-template.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_template.Rd`

**Interfaces:**
- Produces: `dcc_template(path = "DCC-cleaning-plan.xlsx",
  language = "zh-CN")`.
- Produces exact sheets: project, source, columns, values, missing,
  multiselect, rules, actions, outputs.

- [x] **Step 1: Write workbook-structure tests**

```r
test_that("dcc_template writes the exact strict workbook", {
  path <- tempfile(fileext = ".xlsx")
  dcc_template(path)
  wb <- openxlsx2::wb_load(path)
  expect_identical(openxlsx2::wb_get_sheet_names(wb),
                   c("project", "source", "columns", "values", "missing",
                     "multiselect", "rules", "actions", "outputs"))
  cols <- openxlsx2::wb_to_df(wb, sheet = "columns", rows = 1:2)
  expect_identical(names(cols), plan_sheet_contracts()$columns)
})
```

- [x] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="template", reporter="summary")'`

- [x] **Step 3: Define sheet contracts and localized labels**

```r
plan_sheet_contracts <- function() {
  list(project = c("key", "value"),
       source = c("key", "value"),
       columns = c("source_name", "name", "type", "role", "required", "label"),
       values = c("variable", "value", "label"),
       missing = c("variable", "source_value", "state"),
       multiselect = c("item", "layout", "source", "option", "delimiter"),
       rules = c("id", "type", "variable", "parameters", "severity"),
       actions = c("rule_id", "action", "parameters"),
       outputs = c("key", "value"))
}
```

- [x] **Step 4: Build the workbook with openxlsx2**

Create each sheet, write stable English headers and Chinese instruction rows,
add validation lists for type/role/state/rule/action/output values, unlock
input ranges with `wb_add_cell_style(..., locked = FALSE)`, protect sheets with
`wb_protect_worksheet()`, and save with `wb_save()`. Do not set a password; the
protection prevents accidental structural edits and is not a security control.

- [x] **Step 5: Check in a reproducible generated template**

`tools/build-template.R` calls the same internal builder used by
`dcc_template()`. Tests compare sheet names, headers, validations, and unlocked
ranges rather than ZIP bytes or timestamps.

- [x] **Step 6: Run tests and commit**

```bash
Rscript tools/build-template.R
Rscript -e 'devtools::test(filter="template", reporter="summary")'
git add R/template.R tools/build-template.R inst/templates \
  tests/testthat/test-template.R NAMESPACE man/dcc_template.Rd
git commit -m "feat(plan): add strict Excel template"
```

### Task 3: Parse Excel and JSON plans with cell-addressed errors

**Files:**
- Create: `R/plan-read.R`
- Create: `R/validation-location.R`
- Create: `tests/testthat/test-plan-read.R`
- Modify: `R/validate.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_read_plan.Rd`

**Interfaces:**
- Produces: `dcc_read_plan(path)` for XLSX or JSON.
- Extends validation rows with `workbook`, `sheet`, `row`, `column`, `cell`.

- [x] **Step 1: Write strict parsing tests**

```r
test_that("Excel plan errors identify the exact cell", {
  path <- invalid_plan_workbook(sheet = "columns", cell = "C3", value = "numbr")
  err <- dcc_validation_errors(dcc_validate_plan(dcc_read_plan(path)))
  expect_identical(err$code, "PLAN_COLUMN_TYPE")
  expect_identical(err$sheet, "columns")
  expect_identical(err$cell, "C3")
  expect_match(err$fix, "numeric")
})

test_that("unknown sheets and columns are not ignored", {
  expect_error(dcc_read_plan(plan_with_extra_sheet()),
               class = "dcc_plan_error")
  expect_error(dcc_read_plan(plan_with_extra_column()),
               class = "dcc_plan_error")
})
```

- [x] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="plan-read", reporter="summary")'`

- [x] **Step 3: Implement exact workbook parsing**

```r
dcc_read_plan <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "json") return(read_plan_json(path))
  if (ext != "xlsx")
    dcc_abort("Plan must be .xlsx or .json.", class = "dcc_plan_error")
  wb <- openxlsx2::wb_load(path, data_only = TRUE)
  expected <- names(plan_sheet_contracts())
  actual <- openxlsx2::wb_get_sheet_names(wb)
  if (!identical(actual, expected))
    dcc_abort("Workbook sheets do not match template 1.0.",
              class = "dcc_plan_error")
  sections <- lapply(expected, function(s) openxlsx2::wb_to_df(wb, sheet = s))
  names(sections) <- expected
  sections_to_plan(sections, source = normalizePath(path))
}
```

- [x] **Step 4: Extend issue construction**

Add location fields to `val_issue()` with empty defaults and use
`openxlsx2::int2col()` plus source row offsets to calculate cell addresses.
JSON plans use a JSON Pointer in `field` and leave workbook coordinates empty.

- [x] **Step 5: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="plan-read|validate", reporter="summary")'
git add R/plan-read.R R/validation-location.R R/validate.R \
  tests/testthat/test-plan-read.R NAMESPACE man/dcc_read_plan.Rd
git commit -m "feat(plan): parse strict plans with cell locations"
```

### Task 4: Add the staff preflight workflow

**Files:**
- Create: `R/check.R`
- Create: `tests/testthat/test-check.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_check.Rd`

**Interfaces:**
- Produces: `dcc_check(data, plan, output_dir = "dcc-check")` returning
  `dcc_check_result` and writing diagnostics only.

- [x] **Step 1: Write immutability and diagnostic tests**

```r
test_that("dcc_check validates and previews without changing input", {
  data <- format_fixture("xlsx")
  before <- unname(tools::md5sum(data))
  out <- tempfile("dcc-check")
  res <- dcc_check(data, valid_plan_workbook(data), out)
  expect_s3_class(res, "dcc_check_result")
  expect_identical(unname(tools::md5sum(data)), before)
  expect_true(file.exists(file.path(out, "validation.xlsx")))
  expect_false(file.exists(file.path(out, "cleaned-data.csv")))
})
```

- [x] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="check", reporter="summary")'`

- [x] **Step 3: Implement preflight orchestration**

Read and validate the plan, create an import spec, call `dcc_import()`, run
`dcc_doctor()` and `dcc_detect()`, then write `validation.xlsx`,
`preview-findings.xlsx`, `staff-report.html`, and `run-summary.txt`. Do not call
`dcc_execute()` with actions and do not write cleaned data or a manifest.

- [x] **Step 4: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="check|import|plan", reporter="summary")'
git add R/check.R tests/testthat/test-check.R NAMESPACE man/dcc_check.Rd
git commit -m "feat(workflow): add staff preflight"
```

### Task 5: Add the plan path to `dcc_run()` without breaking config calls

**Files:**
- Modify: `R/run.R:152`
- Create: `R/run-plan.R`
- Modify: `tests/testthat/test-run.R`
- Modify: `man/dcc_run.Rd`

**Interfaces:**
- Changes signature to `dcc_run(data, config = NULL, output_dir =
  "dcc-results", mode = c("preview", "execute", "verify", "rerun"),
  id_var = NULL, plan = NULL)`.

- [x] **Step 1: Write compatibility and staff-call tests**

```r
test_that("plan path and legacy config calls share results", {
  data <- write_run_csv()
  plan <- valid_plan_workbook(data)
  a <- dcc_run(data, plan = plan, output_dir = tempfile("a"))
  b <- dcc_run(data, dcc_read_plan(plan)$config, tempfile("b"))
  expect_identical(a$result$findings, b$result$findings)
})

test_that("config and plan cannot both be supplied", {
  expect_error(dcc_run(write_run_csv(), config = run_config(),
                       plan = "plan.xlsx"), class = "dcc_run_error")
})
```

- [x] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="run", reporter="summary")'`

- [x] **Step 3: Add one resolver at the top of `dcc_run()`**

```r
resolve_run_inputs <- function(data, config, plan) {
  if (!is.null(config) && !is.null(plan))
    dcc_abort("Supply `config` or `plan`, not both.", class = "dcc_run_error")
  if (!is.null(plan)) {
    p <- dcc_read_plan(plan)
    return(list(data = dcc_import(data, plan_import_spec(p)),
                config = plan_config(p), plan = p))
  }
  if (!inherits(config, "dcc_config"))
    dcc_abort("A dcc_config or plan path is required.", class = "dcc_run_error")
  list(data = data, config = config, plan = NULL)
}
```

The remainder of `dcc_run()` receives resolved objects and continues through
the Phase A atomic staging path.

- [x] **Step 4: Run compatibility tests and commit**

```bash
Rscript -e 'devtools::test(filter="run|config|plan", reporter="summary")'
git add R/run.R R/run-plan.R tests/testthat/test-run.R man/dcc_run.Rd
git commit -m "feat(workflow): accept strict plans in dcc_run"
```

### Task 6: Add localized help and complete staff documentation

**Files:**
- Create: `R/help.R`
- Create: `inst/i18n/zh-CN.csv`
- Create: `inst/i18n/en.csv`
- Create: `tests/testthat/test-help.R`
- Create: `docs/quick-start-zh-CN.md`
- Create: `docs/quick-start-en.md`
- Create: `examples/strict-excel-project/README.md`
- Modify: `README.md`
- Modify: `NAMESPACE`
- Create: `man/dcc_help.Rd`

**Interfaces:**
- Produces: `dcc_help(code = NULL, language = "zh-CN")`.

- [x] **Step 1: Write localization parity tests**

```r
test_that("every public error code has Chinese and English help", {
  zh <- read_i18n("zh-CN")
  en <- read_i18n("en")
  expect_setequal(zh$code, en$code)
  expect_false(anyNA(zh$explanation))
  expect_false(anyNA(zh$fix))
})
```

- [x] **Step 2: Implement `dcc_help()`**

```r
dcc_help <- function(code = NULL, language = "zh-CN") {
  tab <- read_i18n(language)
  if (is.null(code)) return(tab)
  hit <- tab[tab$code == code, , drop = FALSE]
  if (!nrow(hit))
    dcc_abort("Unknown help code: ", code, class = "dcc_help_error")
  hit
}
```

- [x] **Step 3: Write synchronized guides and example project**

Both guides cover installation, template creation, plan editing, `dcc_check()`,
preview, execute, output files, common error codes, and raw-data safety. The
example uses synthetic data and a checked-in strict plan.

- [x] **Step 4: Run the phase gate and commit**

```bash
Rscript -e 'devtools::test(reporter="summary")'
R CMD build .
R CMD check --no-manual DCC_*.tar.gz
git add R/help.R inst/i18n tests/testthat/test-help.R docs \
  examples/strict-excel-project README.md NAMESPACE man/dcc_help.Rd
git commit -m "docs(workflow): add bilingual staff guidance"
```

## Phase C Exit Criteria

- `dcc_template()` produces the exact protected, bilingual, versioned workbook.
- Excel and JSON plans validate to the same strict contract with cell-addressed
  and stable-coded errors.
- `dcc_check()` performs non-mutating preflight and writes actionable diagnostics.
- `dcc_run(data, plan = ...)` shares the Phase A/B engine and defaults to preview.
- Existing positional and named `dcc_config` calls remain compatible.
- Chinese and English help cover every public workflow error code.
- Full tests and `R CMD check` complete without errors or warnings.
