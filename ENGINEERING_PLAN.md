# DCC remediation engineering plan

Status: Approved engineering baseline

Implementation note (2026-07-15): Phase 1 core-correctness contracts are
implemented under capability contract 1.2: stable finding codes and detector
identity, declared YAML rule IDs, explicit terminal dispositions, complete
stage provenance, strict scoring semantics, and atomic run publication.

Purpose: Guide all subsequent DCC remediation, development, review, and release
work until the acceptance gates in this plan are met.

## 1. Remediation objectives

The remediation moves DCC from a package that an experienced R analyst can
trial to a trustworthy, accessible product with these properties:

1. **Trustworthy audit results.** Every finding, disposition, and data change
   has an exact relationship. DCC must not report an unhandled finding as
   handled or silently execute a different action from the one requested.
2. **Implementation and documentation agree.** Stable documentation describes
   only implemented and verified capabilities. Incomplete work is explicitly
   marked Experimental or Planned.
3. **Survey staff can use the package with limited technical knowledge.** A
   user should not need to understand `data.table`, S3 internals, or complex R
   syntax to complete a standard cleaning workflow.
4. **General-purpose AI systems can use the package reliably.** Machine-readable
   contracts must expose supported capabilities, inputs, outputs, validation
   rules, and unsupported operations.
5. **The package meets a formal release threshold.** Correctness, tests,
   performance, documentation, compatibility, human usability, and AI
   usability must all pass before a stable release.

## 2. Scope and boundaries

### 2.1 In scope

- The Detect -> Execute -> Report workflow.
- The YAML rule engine and five survey-quality detectors.
- Findings, audit logs, provenance, manifests, and reruns.
- CSV/TSV, Excel, SPSS, Stata, SAS, JSON, Parquet, and Feather input.
- Chunked detection.
- Scoring and multi-form mapping.
- Management and audit reports.
- A simplified workflow for survey staff.
- Machine-readable contracts for AI systems.
- Essential Chinese and English documentation.
- CRAN-grade checks and performance benchmarks.

### 2.2 Out of scope

- IRT, CTT, and other statistical modelling.
- Automatically selecting business rules or statistical thresholds.
- Automatically selecting an imputation model.
- Cloud upload or remote processing of survey data.
- Survey hosting, questionnaire publishing, or data collection.
- A general-purpose ETL platform.
- Enterprise authorization and multi-user workflow management.

### 2.3 High-risk function boundary

The `impute` and `deductive-correct` actions must not be implemented merely
because the draft design mentions them.

- `deductive-correct` may be implemented only when a declared rule uniquely
  determines the replacement value.
- General statistical `impute` remains Planned until a separate statistical
  methods, bias, and business validation process is approved.
- Thresholds involving statistical assumptions must be selected by a user,
  supplied by an approved template, or approved by a qualified specialist.
- The default workflow detects and previews; it does not alter data.
- Raw input files are never overwritten.
- Unknown actions and ambiguous decisions must fail validation instead of
  silently degrading to `flag`.

## 3. Engineering principles

1. Correctness takes priority over compatibility; compatibility takes priority
   over convenience.
2. Every automatic change requires an explicit rule and an audit record.
3. Ambiguous situations stop or request confirmation; DCC must not guess.
4. Documentation must not lead implementation.
5. High-level and low-level APIs use the same execution engine.
6. Human errors are explained in plain language; programmatic errors remain
   structured and machine-readable.
7. Every material product promise has an automated test.
8. Missing optional dependencies produce directly actionable guidance.
9. All user input supports validation and preview before execution.
10. Findings and audit logs are long-term public contracts and require a
    migration path when changed.

## 4. Delivery process

### Phase 0: Freeze the specification and baseline

Estimate: 2-3 working days.

#### Work

- Create a capability matrix linking product promise, implementation, tests,
  and documentation.
- Inventory every public function, rule type, action type, and file format.
- Classify each capability as Stable, Experimental, Planned, or Removed.
- Freeze the target findings and audit-log contracts.
- Decide the release and compatibility strategy.
- Preserve current tests, checks, and benchmark results as the pre-remediation
  baseline.

#### Version strategy

- `1.0.1`: severe correctness fixes that do not change valid public usage.
- `1.1.0`: additive contracts such as `finding_id`, simplified entry points,
  validators, and AI specifications.
- `2.0.0`: only if an incompatible findings or audit-log migration is required.

YAML detector identifiers use a compatibility transition:

- The declared YAML `id` becomes the resulting `check_id`.
- Direct calls to `detect_*()` retain their existing `Q_*` identifiers.
- During one transition release, action resolution accepts the declared ID and
  the legacy `Q_*` ID.
- Legacy use emits a deprecation warning.
- The next major release removes legacy action-ID compatibility.

#### Gate

- Every design promise has an explicit status.
- No undocumented gap remains between claimed and implemented capabilities.
- The compatibility strategy is approved.
- The P0 and P1 issue lists are frozen.

### Phase 1: Restore audit and data correctness

Estimate: 1.5-2 weeks. This phase blocks every stable release.

#### Unique finding identity

Generate a stable `finding_id` from the run, check, record, variable, and
occurrence. Every audit row references its finding ID. The model must support:

- One rule affecting several variables on one record.
- Several findings on one cell.
- One finding producing several audit rows.
- Record exclusion as a terminal disposition.
- A reviewed `flag` disposition with no data change.

#### Reconciliation

Replace loose `record_id + check_id` matching. Every finding has exactly one
terminal status:

- `changed`
- `excluded`
- `flagged`
- `skipped`
- `failed`
- `unhandled`

Every audit row must resolve to an exact `finding_id`.

#### No silent action failures

The following conditions must fail validation or produce an explicit `failed`
status:

- A recode map does not contain the old value.
- `actions` contains an unknown rule ID.
- A finding refers to an unknown variable or record ID.
- Record IDs are missing or duplicated.
- A record-level finding receives a cell-level action.
- A group-level finding receives `exclude` or `set_na`.
- A custom scoring function returns the wrong type or length.

#### Complete provenance

The final object records the actual sequence, for example:

```text
read -> l0_validate -> detect -> execute -> map_forms -> score -> report
```

Each stage records input and configuration hashes, parameters, counts, package
version, start and end times, and outcome.

#### Numeric and missing-value semantics

- A range rule produces an `INVALID_NUMERIC` finding for unparseable values.
- Conversion failures cannot silently become undetected `NA` values.
- With `omit_policy = "na"`, a row with only structural missingness has an `NA`
  total score.
- DCC explicitly distinguishes not administered, respondent omission, import
  missingness, and a value cleared by cleaning.
- The distinction is present in scoring provenance and reports.

#### Rule identifiers

- A YAML rule's declared `id` becomes its public `check_id`.
- Detector implementation type remains separate metadata.
- Actions are configured with public rule IDs.
- Unused or unknown action IDs fail during preview.

#### Gate

- Every finding resolves to an exact disposition.
- Removing an audit row makes reconciliation fail.
- An unmapped recode is never reported as handled.
- Final provenance includes Detect.
- Invalid numeric values are detected.
- Fully structural missingness does not become a zero score.
- Core closed-loop property tests pass 1,000 generated cases.
- All P0 correctness issues are closed.

### Phase 2: Repair chunking, formats, and performance

Estimate: 1-1.5 weeks.

#### CSV and TSV chunking

- Infer tab for `.tsv` and comma for `.csv`, with an explicit override.
- Correct `colClasses` handling so first-chunk types are actually locked.
- Produce no warnings in chunked tests.
- Test quoted delimiters and embedded newlines.
- Test exact chunk-size multiples and later all-`NA` chunks.
- Test UTF-8 and latin1 inputs.
- Give a clear conversion workflow for GB18030 and BIG5 chunked input.

#### Arrow backend

- Test multi-batch Parquet and Feather input.
- Cover integer, floating-point, character, logical, date, and missing values.
- Add compatibility tests for supported Arrow versions.
- Require row-level equality with in-memory findings.

#### Format matrix

CI covers CSV, TSV, JSON, Excel, SPSS, Stata, SAS, Parquet, and Feather. SAS
uses a fixed synthetic `.sas7bdat` fixture.

#### Performance targets

At one million rows:

- Read: no more than 15 seconds.
- Detect: no more than 15 seconds.
- Execute: no more than 45 seconds.
- Chunked CSV: no more than 15 seconds.
- Peak memory has a measured, documented ceiling.

Ten-million-row testing runs periodically or manually rather than on every PR.

#### Gate

- Chunked tests have no warnings.
- CSV and TSV defaults are correct.
- All format tests pass.
- Chunked and in-memory findings agree.
- Million-row execution retains at least 25% headroom.
- No material O(n^2) path remains.

### Phase 3: Align functionality and design

Estimate: 1-2 weeks, depending on the retained scope.

#### Recommended for implementation

`dcc_apply_codebook()` supports variable names, value recodes, variable and
value labels, missing-value declarations, type requirements, and ID/group/
weight/item roles. It provides a dry run before applying changes.

`dcc_to_irtc()` is implemented only if the IRTC contract is stable and can be
tested. Otherwise, it is removed from Stable documentation and marked Planned.
Its verified output contract includes `resp`, `pid`, `group`, `pweights`, `Q`,
and anchor information.

Common skip logic becomes declarative rather than requiring embedded R:

```yaml
type: skip_logic
when:
  variable: q1
  equals: 2
then_not_required: [q2, q3, q4]
```

The missing-items detector consumes the resulting structural-missingness map.

#### Recommended for deferral

- General statistical imputation.
- DuckDB backend.
- PDF output.
- Arbitrary deductive correction.
- Psychometric analysis.

Deferred functions are removed from Stable claims.

#### Documentation synchronization

- README references to `dcc_*()` must resolve to real exported functions.
- Every design capability carries a status.
- NAMESPACE, Roxygen, and Rd are generated and checked together.
- Every exported function has a runnable example.
- Examples cannot call unimplemented capabilities.

#### Gate

- Stable documentation contains no fictional capability.
- Every Stable capability has an end-to-end test.
- Codebook and IRTC functions are either complete or explicitly out of scope.
- Skip logic and missing-items detection pass an end-to-end test.

### Phase 4: Make DCC accessible to survey staff

Estimate: 2-3 weeks.

#### One-command workflow

Provide a high-level entry point such as:

```r
dcc_run(
  data = "responses.xlsx",
  config = "cleaning-plan.xlsx",
  output_dir = "dcc-results",
  mode = "preview"
)
```

Supported modes include `preview`, `execute`, `verify`, and `rerun`.

The output layout is fixed:

```text
dcc-results/
|-- cleaned-data.csv
|-- findings.xlsx
|-- audit-log.csv
|-- management-report.html
|-- audit-report.html
|-- manifest.yaml
`-- run-summary.txt
```

#### Excel configuration template

Survey staff can specify the data file, record ID, item columns, allowed values,
ranges, skip conditions, attention checks, response-time limits, missingness
thresholds, and dispositions in Excel. DCC converts the workbook to its
internal rules; staff do not need to write YAML.

#### Validation tools

Provide:

```r
dcc_validate_config()
dcc_validate_rules()
dcc_validate_data()
dcc_doctor()
```

Messages explain what failed, why, and how to correct it. Each message also has
a structured code, severity, field, affected rows, and suggested fix.

#### Local assistant

An optional `dcc_assistant()` runs locally and guides users through file
selection, preview, ID and item selection, presets, findings review, action
confirmation, and export. Survey data is never uploaded.

#### Documentation and examples

Ship a Chinese five-minute introduction, full workflow, Excel-user guide,
survey rule templates, troubleshooting guide, findings interpretation guide,
and sensitive-data guidance. Maintain synchronized English versions.

Bundled synthetic examples cover a basic survey, skip logic, multi-form tests,
attention checks, response-time anomalies, scoring, and a complete audit report.

#### Gate

At least eight survey workers unfamiliar with R participate in usability tests:

- At least 80% complete a standard cleaning task within 30 minutes.
- At least 80% distinguish preview from execution.
- At least 80% find and export findings, cleaned data, and audit reports.
- Critical misuse rate is zero.
- Raw data overwrite count is zero.
- System Usability Scale score is at least 75.
- No developer modifies R code during the task.

Without the Excel workflow or guided assistant, DCC cannot claim that
non-programmers can use it easily.

### Phase 5: Make DCC reliable for general-purpose AI

Estimate: 1-2 weeks.

#### Machine-readable capabilities

Provide a versioned capability document and `dcc_capabilities()` describing
Stable, Experimental, Planned, and unsupported features; rule and action types;
and input formats.

#### Schemas

Publish JSON Schema or an equivalent formal specification for YAML rules,
actions, the Excel cleaning plan, answer keys, form-item maps, manifests,
findings, and audit logs.

#### AI guide

Add `AI_USAGE.md` with the minimal flow, approved public functions, complete
rule and action examples, unsupported operations, validate-before-execute
instructions, success checks, error handling, raw-data safety, and expected
outputs.

#### Public accessors

Replace dependence on hidden attributes with accessors such as:

```r
dcc_mapping_findings()
dcc_item_map()
dcc_validation_errors()
dcc_run_files()
```

#### Safe AI workflow

The documented order is:

```text
capabilities
-> validate configuration
-> preview findings
-> validate actions
-> execute
-> reconcile
-> export
-> verify manifest
```

AI systems must not skip preview or reconciliation by default.

#### Gate

At least three general-purpose AI models run a fixed 20-task suite:

- At least 90% of tasks produce a runnable call within two attempts.
- All models identify unsupported capabilities.
- Unknown rule IDs never continue silently.
- All execution tasks validate or preview first.
- No task overwrites raw input.
- All successful tasks locate their output files.
- Failed complex tasks correct or refuse rather than claim false success.

### Phase 6: Release acceptance and migration

Estimate: 1 week.

#### Automated gates

```text
R CMD check: 0 ERROR / 0 WARNING / 0 NOTE
testthat: 0 failure / 0 skip / 0 warning
markdownlint: 0 error
link check: 0 error
```

Coverage targets:

- At least 90% overall line coverage.
- At least 95% in audit, execution, rules, and rerun modules.
- Every public behavior has a regression test.
- Every previously identified defect has a dedicated test.

Required test layers include unit, end-to-end, property, golden audit-log,
documentation example, format matrix, fault injection, duplicate/missing ID,
duplicate finding, invalid configuration, manifest tampering, migration, AI
configuration validation, and million-row performance tests.

#### Human sign-off

- The R package maintainer approves code, compatibility, and CRAN readiness.
- The survey owner approves rule meaning and report interpretation.
- The audit/quality owner approves reconciliation, lineage, and reproduction.

#### Release artifacts

- R package release.
- Migration guide.
- CHANGELOG and NEWS.
- Capability status matrix.
- Chinese and English guides.
- Excel templates and example project.
- AI usage specification.
- Performance report.
- Usability acceptance record.
- Audit-correctness evidence.

## 5. Acceptance targets

### 5.1 Core correctness

- Every finding has a unique `finding_id`.
- Every audit row references exactly one finding.
- Reconciliation has no false positives.
- An unmapped recode is not successful.
- An unknown action ID does not silently become `flag`.
- Provenance contains every completed stage.
- Raw data is never overwritten.
- Invalid numeric input cannot evade range checks.
- Omission and not-administered states remain distinct.
- Manifests detect input, rule, and version changes.

### 5.2 Functionality

- Every Stable function exists and is tested end to end.
- Every supported format is verified.
- Chunked and in-memory findings agree.
- Tests produce no warnings.
- Million-row performance retains adequate headroom.

### 5.3 Survey staff

- Staff can use DCC without writing YAML or understanding `data.table`.
- Excel templates and the assistant support the standard workflow.
- Preview precedes execution by default.
- Output locations are fixed and obvious.
- Errors explain location, cause, and correction.

### 5.4 AI systems

- AI can query real capabilities and formal schemas.
- AI validates configurations before execution.
- AI identifies unsupported functionality.
- AI uses public accessors rather than hidden attributes.
- AI cannot mistake silent degradation for success.
- AI verifies reconciliation and the manifest.

## 6. Estimate and staffing

For one engineer experienced in R package development:

| Phase | Estimate |
| --- | ---: |
| Specification freeze | 2-3 days |
| Audit and correctness | 1.5-2 weeks |
| Chunking, formats, performance | 1-1.5 weeks |
| Function and documentation alignment | 1-2 weeks |
| Survey-staff usability | 2-3 weeks |
| AI usability | 1-2 weeks |
| Release acceptance | 1 week |

The total estimate is 8-12 weeks without a mature GUI. A production-quality
local no-code interface adds approximately 3-5 weeks and requires continuous
participation from survey staff.

## 7. Completion rule

Remediation is complete only when all of these conditions hold:

1. All P0 and P1 issues are closed.
2. Audit-loop property tests pass.
3. Package checks are 0/0/0.
4. Tests have no warnings or skips.
5. Documentation matches capability status.
6. Million-row performance has at least 25% safety headroom.
7. Survey-staff usability acceptance passes.
8. General-purpose AI task acceptance passes.
9. Migration documentation and compatibility tests are complete.
10. Engineering, survey, and audit owners sign off.

Until these gates pass, DCC is a technical preview and must not claim that
non-technical survey staff or general-purpose AI systems can use it
independently and reliably.
