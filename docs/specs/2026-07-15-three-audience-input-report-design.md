# DCC Three-Audience Input, Workflow, and Reporting Design

Status: Approved design, pending written-spec review

Date: 2026-07-15

Owner: WEIAN DATA Engineering

Related: `ENGINEERING_PLAN.md`

## 1. Purpose

DCC must be safe and usable for three audiences without maintaining three
different cleaning engines:

1. survey staff who do not know programming or statistics;
2. statisticians who use R and need full methodological control;
3. AI agents that require deterministic, machine-readable contracts.

The package will use one validated data contract, one rule engine, one audit
model, and one normalized report model. Each audience receives a different
entry point and presentation over those shared components.

This design extends the existing correctness-remediation work. Expansion of
formats, templates, and reports must not begin until the P0 correctness issues
identified in the remediation review are closed.

## 2. Product principles

1. Raw input is immutable and is never overwritten.
2. DCC does not guess a data structure and then silently execute against it.
3. Every import decision is declared in a strict, versioned plan.
4. Preview is the default; execution is always explicit.
5. Simple APIs and advanced APIs call the same implementation.
6. Human and machine reports are projections of one normalized report model.
7. A supported format is Stable only after semantic and cross-platform tests.
8. Format, validation, execution, and report failures are structured and
   cannot silently degrade.
9. All formally supported format dependencies are installed with DCC.
10. DCC remains one user-facing R package for both CRAN and internal release.

## 3. System architecture

The canonical flow is:

```text
multi-format source file
-> registered format adapter
-> strict import mapping
-> canonical DCC data
-> strict cleaning plan
-> validation
-> preview
-> execution
-> reconciliation and verification
-> normalized report model
-> staff, statistical, and AI outputs
```

The system is divided into six bounded components:

1. **Format adapter registry:** identifies a declared format and delegates
   inspection and reading to one adapter.
2. **Import-plan validator:** validates source location, worksheet/range,
   encoding, field mapping, types, value labels, missing codes, and
   multi-select representation.
3. **Canonical data contract:** stores rectangular data plus explicit metadata
   for variables, values, missingness, roles, source location, and provenance.
4. **Cleaning engine:** performs detection, preview, execution, scoring,
   reconciliation, manifest generation, and rerun.
5. **Normalized report model:** represents every run fact once, independent of
   its eventual Excel, HTML, JSON, or JSONL rendering.
6. **Audience renderers:** expose the shared facts at the appropriate level of
   detail for staff, statisticians, and AI agents.

No renderer may recompute quality counts or cleaning conclusions. No format
adapter may contain cleaning business logic.

## 4. Format adapter registry

### 4.1 Adapter contract

Every adapter implements the same internal responsibilities:

- declare its format name, extensions, dependency, and contract version;
- inspect the declared file without changing it;
- validate format-specific import-plan fields;
- read a declared worksheet, range, delimiter, encoding, or object;
- return canonical values and source metadata;
- report preserved and lost semantics;
- expose availability and limitations through `dcc_capabilities()`.

The registry is internal to the single DCC package. Users do not call reader
packages directly and do not install separate DCC adapter packages.

### 4.2 Target format families

The certified format matrix covers:

| Family | Target formats |
| --- | --- |
| Spreadsheets | XLSX, XLS, XLSB, ODS |
| Delimited and text | CSV, TSV, declared-delimiter TXT, fixed-width text |
| Structured text | JSON, JSONL |
| SPSS | SAV, ZSAV, POR |
| Stata | DTA |
| SAS | SAS7BDAT, XPT |
| Columnar | Parquet, Feather/Arrow |
| R | one-object RDS |
| Compression | Gzip for supported text; ZIP with an explicitly named member |

RData workspaces are excluded because they can contain multiple ambiguously
named objects. Password-protected files are rejected with an actionable error;
DCC does not request or store passwords.

### 4.3 Character encodings

Text adapters formally support explicit UTF-8, UTF-8 BOM, GB18030, GBK, BIG5,
Latin-1, and Windows-1252 declarations. Other encodings may be accepted only
when the installed conversion backend reports deterministic support and the
plan names the encoding explicitly.

Encoding detection is diagnostic only. It may warn that the declared encoding
looks inconsistent, but it cannot replace the plan value during execution.
Spreadsheet cells are Unicode; their import contract concerns cell semantics
such as date systems, numeric display, formula results, labels, and leading
zeros rather than a fictional workbook character encoding.

### 4.4 Stable status

A format becomes Stable only when tests demonstrate preservation or explicit
reporting of:

- numeric, character, logical, date, datetime, and identifier types;
- labels and labelled missing values where the format supports them;
- blank, import-missing, and declared special-missing values;
- Chinese and Latin text;
- row order, column order, and record identity;
- large-file and chunked behavior where applicable;
- equivalent findings after canonicalization;
- Windows, macOS, and Linux behavior.

Formats that can be read but have not passed this matrix are Experimental and
must not appear as Stable in documentation or templates.

## 5. Canonical DCC data contract

Canonical DCC data consists of:

- a rectangular response table;
- a variable dictionary with canonical name, source name, type, label, role,
  source sheet/range, and transformation history;
- value dictionaries with codes and labels;
- explicit missing-state metadata;
- multi-select item definitions;
- source and import-plan hashes;
- an append-only provenance chain.

Missing values have distinct semantic states:

- `not_administered`;
- `respondent_omission`;
- `import_missing`;
- `declared_missing_code`;
- `cleared_by_cleaning`.

The visible data may use `NA`, but the semantic state must remain available
through a public accessor and must be consumed by scoring and reporting. A row
whose scored items are entirely structural missingness has an `NA` total under
`omit_policy = "na"`.

Multi-select responses may originate as wide indicator columns, a delimited
cell, or a long response table. The import plan must declare the representation
and map it to a canonical option-set representation. DCC never infers the
representation from values alone.

## 6. Strict Excel project plan

### 6.1 Workbook structure

`dcc_template()` creates a versioned workbook with these sheets:

| Sheet | Responsibility |
| --- | --- |
| `project` | Template version, project identity, language, source, run defaults |
| `source` | Format, path, worksheet/object, range, header, delimiter, encoding |
| `columns` | Source and canonical names, types, roles, required status |
| `values` | Value codes and labels |
| `missing` | Missing codes and their semantic states |
| `multiselect` | Item, source layout, options, delimiter or indicator mapping |
| `rules` | Detection and validation rules |
| `actions` | Explicit dispositions for public rule IDs |
| `outputs` | Language, audience outputs, sensitive-data controls, file formats |

The template uses protected structure, data-validation lists, concise Chinese
instructions, field examples, and stable machine-readable column names. Cells
intended for user input remain editable; structural cells are protected.

### 6.2 Validation behavior

Unknown sheets, unknown columns, duplicate keys, ambiguous mappings, invalid
enumerations, and missing required fields are errors. Every workbook issue
returns:

- workbook and sheet;
- row and column or cell address;
- stable error code;
- severity;
- plain-language explanation;
- suggested correction;
- machine-readable context.

Invalid numeric parameters cannot silently become missing values. The workbook
template version is mandatory, and unsupported versions stop before import.

## 7. Audience interfaces

### 7.1 Survey staff

The primary staff API is deliberately small:

```r
dcc_template(path = "DCC-cleaning-plan.xlsx", language = "zh-CN")
dcc_check(data, plan, output_dir = "dcc-check")
dcc_run(data, config = NULL, output_dir = "dcc-results",
        mode = "preview", plan = NULL)
dcc_help(code = NULL, language = "zh-CN")
```

Staff call `dcc_run(data, plan = "DCC-cleaning-plan.xlsx")`; the `config`
argument remains for compatibility with existing `dcc_config` objects.
Supplying both `config` and `plan` is an error. `dcc_check()` is the fast
preflight that validates the file and renders workbook diagnostics without
running the full cleaning pipeline. `dcc_run()` defaults to a full preview;
data changes require `mode = "execute"`. Common use must not require knowledge
of data frames, S3 internals, formulas, or reader packages.

### 7.2 Statisticians

The existing staged APIs remain public and are strengthened rather than
replaced:

```r
dcc_import()
dcc_validate_data()
dcc_detect()
dcc_execute()
dcc_score()
dcc_reconcile()
dcc_report()
dcc_manifest()
dcc_rerun()
```

Statisticians can inspect the canonical dictionary, missing states, import
mapping, rule parameters, provenance, and performance data. Validated custom
scoring and extension functions remain possible, with strict return-type and
length checks.

### 7.3 AI agents

AI agents use public interfaces and formal contracts:

```r
dcc_capabilities()
dcc_schema()
dcc_validate_plan()
dcc_run_spec()
dcc_result_summary()
```

Every parameter and result has a schema. AI agents do not parse console text,
read hidden attributes, infer undeclared input semantics, or bypass validation
and preview. Runs have stable IDs, explicit terminal status, output locations,
and integrity counts.

## 8. Execution, error, and provenance model

### 8.1 Atomic execution

Each run writes to a temporary directory named for its `run_id`. DCC publishes
the directory to the requested output location only after required outputs,
reconciliation, and manifest verification succeed. Raw files are never
modified. A failed run cannot leave a directory that looks complete.

Publication rules are explicit:

- `success` and `preview` bundles are atomically renamed to the requested
  output directory after their required artifacts validate;
- `partial_failure` bundles are published as
  `<output_dir>.partial-<run_id>` with a machine-readable missing-artifact
  inventory and a prominent status marker;
- `failed` bundles contain diagnostics only and are published as
  `<output_dir>.failed-<run_id>`;
- a partial or failed run never occupies the requested successful-output path.

### 8.2 Statuses

Run status is one of:

- `preview`;
- `success`;
- `partial_failure`;
- `failed`.

Finding disposition is one of:

- `changed`;
- `excluded`;
- `flagged`;
- `skipped`;
- `failed`;
- `unhandled`.

All errors contain a stable class and code, stage, severity, human message,
suggested fix, and structured location/context. Unknown rules, actions,
formats, fields, records, or values never degrade to a default action.

### 8.3 Provenance

Every stage records:

- start and end time;
- DCC and dependency versions;
- input, plan, configuration, and output hashes;
- declared parameters;
- input and output counts;
- warnings and errors;
- terminal outcome.

The chain includes import, structural validation, detection, execution,
mapping, scoring, reconciliation, reporting, export, and manifest verification
when those stages run.

## 9. Normalized report model

The report model is the sole source of report facts. It contains:

- run identity and status;
- input and plan metadata;
- validation results;
- findings and dispositions;
- changes and exclusions;
- reconciliation and integrity counts;
- before/after summaries;
- scoring and mapping summaries;
- provenance, performance, and hashes;
- output inventory and sensitivity classification.

Renderers may filter, aggregate, translate, or redact this model. They may not
recalculate counts or change statuses.

## 10. Report outputs

### 10.1 Survey-staff outputs

Every successful or preview run produces:

- `staff-results.xlsx`;
- `staff-report.html`;
- `run-summary.txt`.

The Excel workbook uses localized display names and fixed sheet order:

1. Run overview
2. Import checks
3. Blocking errors
4. Findings summary
5. Items needing review
6. Applied changes
7. Excluded records
8. Output-file guide

Staff reports explain what happened, how many records are affected, and what
the user should do next. They do not require interpretation of internal R
types or statistical implementation details.

### 10.2 Statistical outputs

Statistical outputs include:

- `statistical-report.html`;
- complete findings, audit log, reconciliation, and provenance;
- before/after missingness, distribution, and type summaries;
- summaries by rule, variable, severity, and group;
- scoring, skip-logic, form-mapping, and anomaly parameters;
- reproducible calls, versions, hashes, time, and peak memory.

Complete large tables use Parquet and CSV. Excel output is produced only when
the row, column, and cell limits can hold the complete object. DCC reports the
chosen representation and never silently truncates a file.

### 10.3 AI outputs

Machine outputs use a fixed directory:

```text
machine/
|-- run.json
|-- validation.json
|-- summary.json
|-- findings.jsonl
|-- audit-log.jsonl
|-- reconciliation.jsonl
|-- provenance.json
|-- manifest.json
`-- schemas/
```

Every machine object includes `contract_version`, `run_id`, `status`, stable
codes, severity, messages and suggested fixes where applicable, hashes,
integrity counts, and schema version.

### 10.4 Report safety

HTML is self-contained and does not call external services. PDF is not a fixed
output. Potentially identifying raw values are redacted or capped by default
in summary reports. Full audit exports are separate, clearly marked sensitive
artifacts. A required-renderer failure produces `partial_failure` or `failed`;
it cannot be omitted silently.

## 11. Dependencies and distribution

DCC is one user-facing package. The implementation selects one maintained
backend per format family and avoids duplicate libraries that serve the same
contract. All dependencies required by formally supported formats are installed
with DCC and are accessed only through the internal adapter interfaces.

CRAN and the internal complete distribution use the same source. The internal
distribution adds a tested dependency lock and installation verification for
Windows, macOS, and Linux. `dcc_doctor()` reports adapter health, dependency
versions, system capabilities, and formats that cannot currently satisfy their
contract.

## 12. Verification and acceptance

### 12.1 Automated gates

- R CMD check: 0 errors, 0 warnings, 0 notes.
- Test suite: 0 failures, 0 warnings, 0 skips in the complete release image.
- Overall line coverage: at least 90%.
- Import, validation, rules, execution, audit, rerun, and report model: at
  least 95% line coverage.
- Unit, integration, property, format-matrix, round-trip, golden-output,
  fault-injection, migration, and documentation-example tests pass.
- Staff, statistical, and AI report counts and statuses are identical.
- One-million-row execution retains at least 25% headroom against its published
  budget and records peak memory.
- Every Stable format passes Windows, macOS, and Linux certification.

### 12.2 Format fault matrix

Tests cover empty and corrupt files, empty sheets, repeated fields, hidden rows
and columns, mixed types, leading zeros, scientific notation, date systems,
formula results, encodings, missing codes, labels, multi-select layouts,
compression, exact chunk boundaries, large inputs, and backend-version
compatibility.

### 12.3 Human and AI acceptance

For survey staff unfamiliar with R and statistics:

- at least 80% complete template, check, preview, and export within 30 minutes;
- at least 80% distinguish preview from execution;
- no participant modifies R code;
- raw-file overwrite count is zero;
- System Usability Scale score is at least 75.

For statisticians:

- all rules, parameters, missing semantics, and transformations are reviewable;
- manifests reproduce the run;
- statistical summaries and audit counts reconcile.

For AI agents:

- at least 90% of a fixed task suite succeeds within two attempts;
- every execution validates and previews first;
- unsupported or ambiguous input is identified;
- no task reads hidden attributes or parses console prose;
- failed tasks correct or refuse rather than report success.

## 13. Delivery sequence

### Phase A: Core correctness

Close invalid-numeric detection, all-structural-missing scoring, YAML public
rule IDs, manifest failure, terminal disposition, provenance, and contract
documentation defects.

### Phase B: Canonical import platform

Build the canonical data contract, adapter registry, format capabilities,
encoding rules, format matrix, and cross-platform certification.

### Phase C: Strict Excel project plan

Build the versioned workbook, cell-addressed validation, `dcc_template()`,
`dcc_check()`, and the simplified path-based `dcc_run()` workflow.

### Phase D: Normalized reporting

Build the report model and the staff, statistical, and AI renderers, including
large-output and sensitive-data policies.

### Phase E: Product acceptance

Complete the three-audience task suites, coverage, fault injection, performance
and memory tests, CRAN checks, internal release image, guides, templates,
example project, migration guide, and acceptance records.

Every phase produces an installable, testable, reversible release. Later
phases reuse earlier public contracts and cannot copy or fork cleaning logic.

## 14. Compatibility and migration

Existing low-level functions remain available. The current `dcc_run(data,
config, output_dir, mode)` form accepts existing `dcc_config` objects. The
additive signature is `dcc_run(data, config = NULL, output_dir,
mode = "preview", plan = NULL)`, and the strict workbook path is supplied
through `plan`. Existing positional and named `config` calls remain valid.
`dcc_read()` remains the direct file reader; `dcc_import()` adds strict-plan
canonicalization over the adapter registry. Findings, audit logs, manifests,
schemas, and capability documents receive explicit contract versions and
migration tests before any incompatible change.

Legacy detector-native `Q_*` identifiers remain valid for direct
`detect_*()` calls. YAML rules use the declared public rule ID, with a
documented compatibility window for legacy action mappings.

## 15. Explicit non-goals

- Cloud upload or remote processing of survey data.
- Survey hosting or questionnaire publishing.
- Automatic selection of statistical thresholds or imputation models.
- General statistical imputation or arbitrary deductive correction.
- A fixed PDF reporting requirement.
- A second cleaning engine for staff or AI callers.
- Automatic execution based on inferred workbook structure.
