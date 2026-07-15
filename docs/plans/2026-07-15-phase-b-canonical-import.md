# Phase B Canonical Import Platform Implementation Plan

> **Execution:** Complete the checked tasks in order, with the stated red/green
> verification and review checkpoint before each commit.

**Goal:** Build one strict canonical import layer and an internal adapter
registry for every certified source format.

**Architecture:** `dcc_read()` becomes a compatibility wrapper over registered
adapters; `dcc_import()` combines a declared import specification with an
adapter and canonicalizes values, dictionaries, missing states, and provenance.
Adapters only read source semantics and never perform cleaning.

**Tech Stack:** R >= 4.1, data.table, stringi, readxl >= 1.5.0,
openxlsx2 >= 1.28, readODS >= 2.3.5, haven >= 2.5.5, arrow, jsonlite,
yaml, testthat.

## Global Constraints

- Phase A is complete and its contract tests pass.
- The caller declares format structure; detection is diagnostic only.
- All formally supported format dependencies are in `Imports`.
- XLSB remains Experimental until its limited openxlsx2 backend passes the full
  three-platform matrix.
- No format is Stable merely because its backend can open a fixture.
- Raw paths and compressed members are never modified.

---

### Task 1: Create the adapter registry

**Files:**
- Create: `R/formats.R`
- Create: `tests/testthat/test-formats.R`
- Modify: `R/capabilities.R`

**Interfaces:**
- Produces: `new_format_adapter(name, extensions, reader, inspector,
  validator, status, semantics)`.
- Produces: `dcc_format_registry()`, `dcc_get_adapter(format)`.

- [ ] **Step 1: Write registry tests**

```r
test_that("format registry has unique names and extensions", {
  reg <- dcc_format_registry()
  expect_false(anyDuplicated(names(reg)))
  ext <- unlist(lapply(reg, `[[`, "extensions"), use.names = FALSE)
  expect_false(anyDuplicated(ext[ext != "txt"]))
  expect_true(all(vapply(reg, inherits, logical(1), "dcc_format_adapter")))
})

test_that("unknown formats fail with a stable error", {
  expect_error(dcc_get_adapter("telepathy"), class = "dcc_format_error")
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="formats", reporter="summary")'`

- [ ] **Step 3: Implement the registry contract**

```r
new_format_adapter <- function(name, extensions, reader, inspector,
                               validator, status, semantics) {
  stopifnot(is.function(reader), is.function(inspector), is.function(validator))
  structure(list(name = name, extensions = extensions, reader = reader,
                 inspector = inspector, validator = validator,
                 status = status, semantics = semantics),
            class = "dcc_format_adapter")
}

dcc_format_registry <- function() {
  list(csv = adapter_delimited("csv", "csv", ","),
       tsv = adapter_delimited("tsv", "tsv", "\t"),
       txt = adapter_text(), fwf = adapter_fwf(), json = adapter_json(),
       jsonl = adapter_jsonl(), xls = adapter_xls(), xlsx = adapter_xlsx(),
       xlsb = adapter_xlsb(), ods = adapter_ods(), spss = adapter_spss(),
       stata = adapter_stata(), sas = adapter_sas(), xpt = adapter_xpt(),
       parquet = adapter_parquet(), feather = adapter_feather(),
       rds = adapter_rds())
}

dcc_get_adapter <- function(format) {
  reg <- dcc_format_registry()
  if (!format %in% names(reg))
    dcc_abort("Unsupported format: ", format, class = "dcc_format_error")
  reg[[format]]
}
```

Adapter constructor functions are supplied by later tasks. Until then, define
test-only minimal stubs with `status = "Planned"` and readers that raise
`dcc_format_error`.

- [ ] **Step 4: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="formats|capabilities", reporter="summary")'
git add R/formats.R R/capabilities.R tests/testthat/test-formats.R
git commit -m "feat(import): add format adapter registry"
```

### Task 2: Extend the canonical data contract

**Files:**
- Create: `R/import-contract.R`
- Modify: `R/dcc_data.R:18`
- Modify: `R/accessors.R`
- Create: `tests/testthat/test-import-contract.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_dictionary.Rd`
- Create: `man/dcc_missing_states.Rd`

**Interfaces:**
- Produces: `new_import_spec(source, format, options, columns, values,
  missing, multiselect)`.
- Extends: `dcc_data(..., dictionary, missing_states, import_spec)`.
- Produces: `dcc_dictionary(x)`, `dcc_missing_states(x)`.

- [ ] **Step 1: Write canonical-contract tests**

```r
test_that("canonical data preserves dictionary and missing semantics", {
  d <- data.table::data.table(sid = c("S1", "S2"), q1 = c(1, NA))
  dict <- data.table::data.table(name = c("sid", "q1"),
                                 source_name = c("编号", "问题1"),
                                 type = c("character", "integer"),
                                 role = c("id", "item"))
  miss <- data.table::data.table(row = 2L, variable = "q1",
                                 state = "respondent_omission",
                                 source_value = NA_character_)
  x <- dcc_data(d, dictionary = dict, missing_states = miss)
  expect_identical(dcc_dictionary(x), dict)
  expect_identical(dcc_missing_states(x)$state, "respondent_omission")
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="import-contract", reporter="summary")'`

- [ ] **Step 3: Add constructors and validation**

```r
missing_state_levels <- function() {
  c("not_administered", "respondent_omission", "import_missing",
    "declared_missing_code", "cleared_by_cleaning")
}

new_import_spec <- function(source, format, options = list(), columns,
                            values = data.frame(), missing = data.frame(),
                            multiselect = data.frame()) {
  structure(list(source = normalizePath(source, mustWork = TRUE),
                 format = format, options = options,
                 columns = data.table::as.data.table(columns),
                 values = data.table::as.data.table(values),
                 missing = data.table::as.data.table(missing),
                 multiselect = data.table::as.data.table(multiselect)),
            class = "dcc_import_spec")
}
```

Extend `dcc_data()` with empty defaults, validate dictionary uniqueness and
missing-state values, and preserve all three objects in every operation that
creates a new `dcc_data`.

- [ ] **Step 4: Add public accessors and run tests**

```r
dcc_dictionary <- function(x) {
  if (!inherits(x, "dcc_data"))
    dcc_abort("`x` must be dcc_data.", class = "dcc_type_error")
  data.table::copy(x$dictionary)
}

dcc_missing_states <- function(x) {
  if (!inherits(x, "dcc_data"))
    dcc_abort("`x` must be dcc_data.", class = "dcc_type_error")
  data.table::copy(x$missing_states)
}
```

Run: `Rscript -e 'devtools::test(filter="import-contract|dcc-data|score|map-forms", reporter="summary")'`

- [ ] **Step 5: Commit**

```bash
git add R/import-contract.R R/dcc_data.R R/accessors.R \
  tests/testthat/test-import-contract.R NAMESPACE \
  man/dcc_dictionary.Rd man/dcc_missing_states.Rd
git commit -m "feat(import): add canonical data metadata"
```

### Task 3: Implement strict `dcc_import()` canonicalization

**Files:**
- Create: `R/import.R`
- Create: `tests/testthat/test-import.R`
- Modify: `NAMESPACE`
- Create: `man/dcc_import.Rd`

**Interfaces:**
- Produces: `dcc_import(path, spec)` returning `dcc_data`.
- Consumes: adapter raw data as character-preserving data.frame plus metadata.

- [ ] **Step 1: Write failing strict-conversion tests**

```r
test_that("dcc_import applies declared names, types and missing codes", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("编号,年龄,性别", "001,23,1", "002,-99,2"), f)
  spec <- import_fixture_spec(f)
  x <- dcc_import(f, spec)
  expect_identical(x$data$sid, c("001", "002"))
  expect_identical(x$data$age, c(23L, NA_integer_))
  expect_identical(dcc_missing_states(x)$state, "declared_missing_code")
})

test_that("undeclared source columns stop import", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("sid,q1,extra", "S1,1,x"), f)
  expect_error(dcc_import(f, import_fixture_spec(f)),
               class = "dcc_import_error")
})
```

- [ ] **Step 2: Confirm red**

Run: `Rscript -e 'devtools::test(filter="import$", reporter="summary")'`

- [ ] **Step 3: Implement the strict pipeline**

```r
dcc_import <- function(path, spec) {
  if (!inherits(spec, "dcc_import_spec"))
    dcc_abort("`spec` must be a dcc_import_spec.", class = "dcc_type_error")
  adapter <- dcc_get_adapter(spec$format)
  issues <- adapter$validator(path, spec)
  if (nrow(dcc_validation_errors(issues)))
    dcc_abort("Import plan validation failed.", class = "dcc_import_error")
  raw <- adapter$reader(path, spec$options)
  canonicalize_import(raw$data, raw$metadata, spec)
}
```

`canonicalize_import()` checks exact source names, applies missing-code masks
before type conversion, rejects every failed conversion with source row and
column, builds dictionaries and missing-state rows, and records file/spec
hashes in import provenance.

- [ ] **Step 4: Add docs, run tests, and commit**

```bash
Rscript -e 'devtools::test(filter="import|encoding", reporter="summary")'
git add R/import.R tests/testthat/test-import.R NAMESPACE man/dcc_import.Rd
git commit -m "feat(import): add strict canonical import"
```

### Task 4: Add text, structured-text, RDS, and compression adapters

**Files:**
- Create: `R/formats-text.R`
- Create: `R/formats-compression.R`
- Create: `tests/testthat/test-formats-text.R`
- Create: `tests/testthat/test-formats-compression.R`
- Modify: `R/encoding.R`

**Interfaces:**
- Implements: CSV, TSV, declared-delimiter TXT, fixed-width, JSON, JSONL, RDS,
  gzip, and explicit ZIP member.

- [ ] **Step 1: Add fixtures and failing format tests**

```r
test_that("JSONL and RDS adapters return rectangular raw data", {
  jl <- tempfile(fileext = ".jsonl")
  writeLines(c('{"sid":"001","q1":"1"}',
               '{"sid":"002","q1":null}'), jl)
  expect_identical(dcc_get_adapter("jsonl")$reader(jl, list())$data$sid,
                   c("001", "002"))
  rd <- tempfile(fileext = ".rds")
  saveRDS(data.frame(sid = "001"), rd)
  expect_s3_class(dcc_get_adapter("rds")$reader(rd, list())$data, "data.frame")
})

test_that("ZIP requires a safe explicit member", {
  expect_error(resolve_compressed_source("x.zip", list()),
               class = "dcc_import_error")
  expect_error(validate_zip_member("../secret.csv"),
               class = "dcc_import_error")
})
```

- [ ] **Step 2: Implement raw readers without type guessing**

Use `data.table::fread(..., colClasses = "character", encoding = declared)`,
`jsonlite::stream_in()` for JSONL, `jsonlite::fromJSON()` for rectangular JSON,
`utils::read.fwf(..., widths = options$widths, colClasses = "character")`, and
`readRDS()` followed by an exact `is.data.frame()` check.

- [ ] **Step 3: Implement safe compression resolution**

```r
validate_zip_member <- function(member) {
  if (grepl("(^/|^[A-Za-z]:|(^|/)\\.\\.(/|$))", member))
    dcc_abort("Unsafe ZIP member path.", class = "dcc_import_error")
  member
}
```

Extract only the declared member into a run-owned temporary directory. Never
call `unzip()` without the `files` argument.

- [ ] **Step 4: Run encoding and format tests, then commit**

```bash
Rscript -e 'devtools::test(filter="formats-text|formats-compression|encoding", reporter="summary")'
git add R/formats-text.R R/formats-compression.R R/encoding.R \
  tests/testthat/test-formats-text.R tests/testthat/test-formats-compression.R
git commit -m "feat(import): add strict text and compressed adapters"
```

### Task 5: Add spreadsheet adapters

**Files:**
- Create: `R/formats-spreadsheet.R`
- Create: `tests/testthat/test-formats-spreadsheet.R`
- Create: `tests/fixtures/formats/README.md`
- Modify: `DESCRIPTION`

**Interfaces:**
- Implements: XLS via readxl, XLSX via readxl, ODS via readODS, XLSB via
  openxlsx2 with Experimental status.

- [ ] **Step 1: Add typed spreadsheet fixtures and failing parity tests**

```r
test_that("spreadsheet adapters preserve declared raw values", {
  expected <- data.frame(sid = c("001", "002"),
                         date = c("2026-07-01", "2026-07-02"),
                         q1 = c("1", "-99"))
  for (fmt in c("xls", "xlsx", "ods")) {
    got <- dcc_get_adapter(fmt)$reader(format_fixture(fmt),
                                       list(sheet = "responses",
                                            range = "A1:C3"))$data
    expect_identical(as.data.frame(got), expected, info = fmt)
  }
})
```

- [ ] **Step 2: Add dependencies to Imports**

```text
    openxlsx2 (>= 1.28),
    readODS (>= 2.3.5),
    readxl (>= 1.5.0),
```

- [ ] **Step 3: Implement XLS/XLSX/ODS readers**

Use `readxl::read_excel(path, sheet = options$sheet,
range = options$range, col_types = "text", .name_repair = "minimal")` and
`readODS::read_ods(path, sheet = options$sheet, range = options$range,
col_types = NA, guess = FALSE, as_tibble = FALSE, .name_repair = "minimal")`.
Reject missing or duplicate names before canonicalization.

- [ ] **Step 4: Implement and constrain XLSB**

Load with `openxlsx2::wb_load(path, sheet = options$sheet,
data_only = TRUE)` and convert the declared range with
`openxlsx2::wb_to_df()`. Record limitations for formulas, validations, pivots,
slicers, and non-little-endian systems. Keep status Experimental until every
Stable certification test passes.

- [ ] **Step 5: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="formats-spreadsheet|import", reporter="summary")'
git add R/formats-spreadsheet.R tests/testthat/test-formats-spreadsheet.R \
  tests/fixtures/formats/README.md DESCRIPTION
git commit -m "feat(import): add spreadsheet adapters"
```

### Task 6: Add statistical and columnar adapters

**Files:**
- Create: `R/formats-statistical.R`
- Create: `R/formats-columnar.R`
- Create: `tests/testthat/test-formats-statistical.R`
- Create: `tests/testthat/test-formats-columnar.R`
- Modify: `DESCRIPTION`

**Interfaces:**
- Implements: SAV/ZSAV/POR, DTA, SAS7BDAT/XPT, Parquet, Feather/Arrow.

- [ ] **Step 1: Write label, missing-tag, and type parity tests**

```r
test_that("statistical adapters retain labels and tagged missings", {
  raw <- dcc_get_adapter("spss")$reader(format_fixture("sav"), list())
  expect_identical(raw$metadata$variables$q1$label, "Question 1")
  expect_true("declared_missing_code" %in% raw$metadata$missing$state)
})

test_that("Parquet and Feather produce equal canonical tables", {
  p <- dcc_import(format_fixture("parquet"), import_fixture_spec("parquet"))
  f <- dcc_import(format_fixture("feather"), import_fixture_spec("feather"))
  expect_identical(as.data.frame(p), as.data.frame(f))
})
```

- [ ] **Step 2: Implement haven dispatch with metadata capture**

Dispatch to `haven::read_sav`, `read_por`, `read_dta`, `read_sas`, or
`read_xpt`. Capture `label`, `labels`, `na_values`, `na_range`, and tagged
missing values before conversion; never call the `zap_*()` functions before
canonical metadata is built.

- [ ] **Step 3: Implement Arrow readers**

Use `arrow::read_parquet(..., as_data_frame = TRUE)` and
`arrow::read_feather(..., as_data_frame = TRUE)`. Preserve Arrow schema text in
adapter metadata and reuse the existing record-batch path for chunked input.

- [ ] **Step 4: Run tests and commit**

```bash
Rscript -e 'devtools::test(filter="formats-statistical|formats-columnar|chunked", reporter="summary")'
git add R/formats-statistical.R R/formats-columnar.R \
  tests/testthat/test-formats-statistical.R \
  tests/testthat/test-formats-columnar.R DESCRIPTION
git commit -m "feat(import): add statistical and columnar adapters"
```

### Task 7: Delegate `dcc_read()`, capabilities, and doctor to the registry

**Files:**
- Modify: `R/dcc_read.R`
- Modify: `R/capabilities.R`
- Modify: `R/validate.R`
- Modify: `tests/testthat/test-dcc-read.R`
- Modify: `tests/testthat/test-capabilities.R`
- Modify: `tests/testthat/test-validate.R`
- Modify: `DESCRIPTION`
- Modify: `README.md`
- Modify: `NEWS.md`

**Interfaces:**
- Preserves: `dcc_read(path, format = "auto", encoding = "auto", ...)`.
- Extends: `dcc_capabilities()$formats` with status, extensions, backend,
  semantics, and limitations.
- Extends: `dcc_doctor(formats = "all")`.

- [ ] **Step 1: Add single-source-of-truth tests**

```r
test_that("reader and capabilities share the registry", {
  reg <- dcc_format_registry()
  caps <- dcc_capabilities()$formats
  expect_setequal(caps$format, names(reg))
  expect_identical(caps$status, vapply(reg, `[[`, character(1), "status"))
})
```

- [ ] **Step 2: Make `dcc_read()` a compatibility wrapper**

Infer only the file format from a unique extension when `format = "auto"`;
build a compatibility import specification from `...`, call the adapter, and
return `dcc_data`. Do not infer sheet, range, encoding, or missing semantics.

- [ ] **Step 3: Make every formal backend an installed dependency**

Move `arrow`, `haven`, `jsonlite`, `openxlsx2`, `readODS`, `readxl`, and `yaml`
to `Imports`. Keep only test/build tools in `Suggests`. Remove runtime
`requireNamespace()` fallbacks for formal formats.

- [ ] **Step 4: Add adapter health to `dcc_doctor()`**

Return one structured issue per missing namespace, unsupported platform,
backend load failure, or version below the declared minimum. Requested-format
failures are blocking; unrelated Experimental backend limitations are warnings.

- [ ] **Step 5: Run the full format and package gate**

```bash
Rscript -e 'devtools::test(reporter="summary")'
R CMD build .
R CMD check --no-manual DCC_*.tar.gz
```

- [ ] **Step 6: Commit**

```bash
git add R/dcc_read.R R/capabilities.R R/validate.R DESCRIPTION \
  tests/testthat/test-dcc-read.R tests/testthat/test-capabilities.R \
  tests/testthat/test-validate.R README.md NEWS.md
git commit -m "feat(import): route input through certified adapters"
```

## Phase B Exit Criteria

- One registry owns every input format, extension, backend, limitation, and
  capability level.
- `dcc_import()` requires an explicit mapping and produces validated canonical
  data with labels, missing states, source locations, and provenance intact.
- Text encodings, compression, spreadsheets, statistical files, and columnar
  formats pass their declared semantic tests without silent guessing.
- Every Stable backend is in `Imports` and installs with DCC.
- XLSB remains Experimental and fails explicitly for unsupported features.
- Existing `dcc_read()` calls remain compatible through the registry.
- Full tests and `R CMD check` complete without errors or warnings.
