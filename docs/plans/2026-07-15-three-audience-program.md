# DCC Three-Audience Implementation Program

**Purpose:** Coordinate the approved DCC redesign without mixing correctness,
format expansion, staff workflow, reporting, and release proof into one unsafe
change set.

**Approved design:**
[`docs/specs/2026-07-15-three-audience-input-report-design.md`](../specs/2026-07-15-three-audience-input-report-design.md)

## Delivery Order

| Phase | Outcome | Prerequisite | Plan |
|---|---|---|---|
| A | Correct, auditable cleaning core | Current package | [Core correctness](2026-07-15-phase-a-core-correctness.md) |
| B | Canonical import and internal adapter registry | A | [Canonical import](2026-07-15-phase-b-canonical-import.md) |
| C | Strict protected Excel plan and four-function staff workflow | A, B | [Strict Excel workflow](2026-07-15-phase-c-strict-excel-workflow.md) |
| D | One report model rendered for three audiences | A, B, C | [Normalized reports](2026-07-15-phase-d-normalized-reports.md) |
| E | Cross-platform acceptance and reproducible release | A-D | [Acceptance and release](2026-07-15-phase-e-acceptance-release.md) |

Phases are intentionally sequential at their public-contract boundaries. Work
inside a phase may be parallelized only when tasks do not edit the same files
or depend on an unfinished contract.

## Non-Negotiable Product Contract

- One public `DCC` package and one cleaning engine.
- Survey staff use a strict, protected, bilingual Excel template and
  `dcc_template()`, `dcc_check()`, `dcc_run()`, and `dcc_help()`.
- Statisticians receive explicit programmatic control, full metadata,
  reconciliation, and reproducible artifacts.
- AI agents receive discovery APIs, stable codes, schemas, deterministic paths,
  structured summaries, and bounded outputs.
- Raw formats enter through explicit adapters and mapping plans; no semantic
  guessing or silent repair.
- All formally supported format backends install with DCC.
- Excel, HTML, and machine outputs are mandatory where selected; PDF is not a
  fixed output requirement.
- Existing public interfaces remain compatible or receive a documented staged
  migration path.

## Capability Policy

`dcc_capabilities()` reports `Stable`, `Experimental`, or `Unavailable`
with backend version and platform evidence. A format becomes `Stable` only
after round-trip/canonical-hash fixtures pass Linux, macOS, and Windows. XLSB
starts as `Experimental` because the selected independent R backend currently
has limited coverage; unsupported workbook features must fail explicitly.

## Checkpoints

At the end of every phase:

1. Run its focused tests and the full test suite.
2. Run `R CMD check` with warnings treated as failures.
3. Review public API, schema, and dependency changes.
4. Update the capability table, `NEWS.md`, and migration notes.
5. Commit the phase as independently reviewable changes.
6. Do not begin the next public contract until the exit criteria pass.

## Final Acceptance Summary

The program is complete only when the same synthetic survey can be entered via
the strict workbook, imported programmatically, and orchestrated through the
machine contract; all three paths must produce the same canonical hashes,
findings, actions, reconciliation totals, and provenance. Audience reports may
differ in presentation and detail, but never in facts.
