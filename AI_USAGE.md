# Using DCC from a general-purpose AI system

This guide is the contract for AI systems that drive DCC through its public R
API. Follow the safe flow below; do not skip validation or preview. DCC never
uploads data and never overwrites raw input.

## Discover the contract first

Query the machine-readable capability document and the formal schemas before
building anything. Do not assume a capability that `dcc_capabilities()` marks
`Planned`.

```r
caps <- dcc_capabilities()
caps$action_types           # exclude, set_na, flag, recode
caps$rule_types             # range, set, expr, and the five detectors
caps$formats                # status, extensions, backend, semantics, limitations
caps$features               # name, status (Stable/Experimental/Planned), since
caps$unsupported            # impute, deductive_correct, irtc, ...

dcc_schema("rules")         # JSON Schema for the YAML rule file
dcc_schema("actions")       # JSON Schema for the action map
dcc_schema("finding")       # JSON Schema for one findings row
dcc_schema("audit_log")     # JSON Schema for one audit-log row
dcc_schema("manifest")      # JSON Schema for a reproducibility manifest
dcc_schema("disposition")   # terminal state for every finding
dcc_schema("provenance")    # stage boundaries, outcome, hashes, counts
dcc_schema("plan")          # strict Excel/JSON project contract
dcc_schema("report-model")  # normalized source shared by all renderers
dcc_schema("summary")       # bounded machine summary
dcc_schema("artifact_manifest")
```

## The safe flow

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

Never call `dcc_execute()` before previewing findings, and never treat a run as
successful without `dcc_reconcile()`.

## Approved public functions

Strict workflow: `dcc_template()`, `dcc_read_plan()`, `dcc_validate_plan()`,
`dcc_check()`, `dcc_run(plan = ...)`, and `dcc_help()`.

Input and detection: `dcc_read()`, `dcc_import()`, `dcc_dictionary()`,
`dcc_missing_states()`, `dcc_rules()`, `dcc_detect()`,
`dcc_detect_chunked()`, `dcc_l0_diagnose()`.

Execution and audit: `dcc_execute()`, `dcc_audit_log()`, `dcc_cleaned()`,
`dcc_reconcile()`, `dcc_trace()`, `dcc_export_log()`, `dcc_unhandled()`,
`dcc_dispositions()`.

Scoring and mapping: `dcc_score()`, `dcc_map_forms()`, `dcc_item_map()`,
`dcc_mapping_findings()`.

Reporting and reproduction: `dcc_report_model()`, `dcc_report_staff()`,
`dcc_report_statistical()`, `dcc_report_machine()`, `dcc_result_summary()`,
`dcc_validate_json()`, `dcc_validate_jsonl()`, `dcc_report()`,
`dcc_manifest()`, `dcc_rerun()`.

Contracts: `dcc_capabilities()`, `dcc_schema()`.

Read results only through these accessors; do not read hidden object
attributes.

For strict imports, never infer columns, types, missing codes, text encoding,
worksheet, range, fixed widths, delimiter, ZIP member, or multi-select layout.
Use the validated import specification from the DCC plan. Check the selected
format's status and limitations before reading; XLSB remains Experimental.

Prefer a JSON plan when generating a project automatically. Validate it against
`dcc_schema("plan")`, then call `dcc_read_plan()` and `dcc_validate_plan()`.
Excel validation reports workbook coordinates; JSON validation reports a JSON
Pointer in `field`. Never add unknown fields or silently repair a rejected
strict plan. Use `dcc_check()` and preview before any explicitly authorized
execute call.

## Machine report contract

For unattended processing, prefer `dcc_run()` with
`include_machine_report = TRUE` in the strict plan, then read only the
published `machine/` directory. Validate `run.json`, `validation.json`,
`summary.json`, `provenance.json`, and `manifest.json` with
`dcc_validate_json()`; validate each JSONL artifact with
`dcc_validate_jsonl()`. Treat paths as deterministic relative paths and action
codes in `next_actions` as codes, not prose. `summary.json` contains the same
run ID, totals, and cleaned/audit hashes used by the staff and statistical
reports. The machine bundle is complete and may contain sensitive row-level
data; do not expose it as a staff report.

Use `dcc_result_summary(result, "compact")` for a bounded in-memory response:
it contains at most 20 deterministically ordered findings and excludes raw
evidence. Request `"full"` only when the caller is authorized for complete
reconciliation and provenance.

## A complete rule set and action map

Rules are declarative YAML. Each check has an `id` (which becomes the public
`check_id` for every rule type) and a `type`.

```yaml
checks:
  - id: R001
    type: range
    variable: score
    min: 0
    max: 100
    severity: fail
  - id: R002
    type: set
    variable: q2
    values: [A, B, C, D]
  - id: D001
    type: missing_items
    items: [q1, q2, q3, q4]
    max_prop: 0.5
```

Actions map a `check_id` to exactly one action. Every action name must match a
`check_id` that actually produced findings; an unused or unknown action ID is
an error.

```r
actions <- list(
  R001 = "set_na",                                  # blank the offending cell
  R002 = list(action = "recode", map = c("9" = "5")), # recode a coded value
  D001 = "flag"                                     # review, keep the data
)
```

Detector findings retain their implementation identity in `detector_id`
(`Q_MISSING_ITEMS`, `Q_STRAIGHTLINING`, `Q_RESPONSE_TIME`, `Q_TRAP_ITEMS`,
`Q_SCORE_OUTLIER`, `Q_GROUP_SCORE_SHIFT`), but actions always map to the YAML
rule's declared `check_id`. Detector-native action aliases from older releases
emit a deprecation warning and are rejected when ambiguous.

## Minimal end-to-end example

```r
x     <- dcc_read("responses.csv")
rules <- dcc_rules("rules.yaml")

# preview: detect only, change nothing
found <- dcc_detect(x, rules, id_var = "sid")

# execute the reviewed action plan (validated before any change)
res <- dcc_execute(x, found,
                   actions = list(R001 = "set_na"),
                   id_var = "sid")

# verify the closed loop before trusting the result
rec <- dcc_reconcile(res)          # one terminal status per finding
stopifnot(!any(rec$status == "unhandled"))  # or handle the unhandled set

# export and record reproduction
dcc_export_log(res, "audit-log.csv", format = "csv")
dcc_manifest(res, path = "manifest.yaml")
dcc_rerun("manifest.yaml")$reproduced       # TRUE when byte-identical
```

## Validation before execution

`dcc_execute()` validates the whole plan before touching data and raises
`dcc_execute_error` on any of: an unknown action ID, an action name outside the
contract, a recode map that does not cover an observed value, a missing or
duplicated record ID, or a cell-level action on a group-level finding. Treat
any such error as a configuration bug to fix, not to retry.

## Success checks

- `dcc_reconcile(res)$status` has no `unhandled` rows you did not intend.
- `dcc_dispositions(res)` contains exactly one terminal row per finding.
- An audit row whose `finding_id` is absent from the findings raises
  `dcc_reconcile_error`; a clean run never triggers it.
- `dcc_rerun(manifest)$reproduced` is `TRUE`.
- Every finding in `dcc_unhandled(res)` is one you deliberately left unactioned.

## Unsupported operations

DCC does not impute values, does not perform arbitrary deductive correction,
and does not run psychometric models. These appear in `caps$unsupported`.
Attempting them is out of scope; do not synthesize a workaround that mutates
data outside the audited action set.

## Raw-data safety

The input file is never modified. `dcc_execute()` copies the data and produces
a new version; the cleaned data and audit log are separate outputs you write
explicitly. Do not overwrite the source file.

## Error handling

All DCC errors carry a structured class (for example `dcc_execute_error`,
`dcc_reconcile_error`, `dcc_type_error`, `dcc_io_error`). Branch on the class
rather than parsing the message. On a failed complex task, correct the
configuration or stop; never report a run as successful when reconciliation or
the manifest check did not pass. A failed `dcc_run()` raises `dcc_run_error`
and publishes machine-readable diagnostics under `.failed-<run_id>`; it never
returns a successful run without a manifest.
