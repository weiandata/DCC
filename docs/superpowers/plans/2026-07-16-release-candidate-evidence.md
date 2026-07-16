# DCC 1.2.0 Release Candidate Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce and verify a DCC 1.2.0 release candidate with an exact first-submission NOTE exception and evidence for all three audiences.

**Architecture:** A small check-result classifier converts raw `R CMD check` output into stable evidence codes. The existing closed release schema and verifier enforce that evidence, while GitHub Actions supplies platform artifacts and strict acceptance workbooks supply human evidence.

**Tech Stack:** R 4.6, testthat, jsonlite, GitHub Actions, `@oai/artifact-tool`, Git.

## Global Constraints

- Only `cran_new_submission` may be non-actionable; all other NOTEs block.
- DCC runtime dependencies remain unchanged and no runtime installer is added.
- PDF remains optional and is not a fixed report output.
- Staff signatures and external CI results must be real, never synthesized.
- All release artifacts identify DCC version `1.2.0` and use SHA-256.

---

### Task 1: Implement the NOTE evidence contract

**Files:**
- Create: `tools/classify-r-check.R`
- Modify: `tools/verify-release.R`
- Modify: `inst/schemas/release-evidence.schema.json`
- Modify: `tests/testthat/test-release-evidence.R`
- Create: `tests/testthat/test-r-check-classifier.R`
- Modify: `.github/workflows/r-check.yml`

**Interfaces:**
- Consumes: `R CMD check` `00check.log` and existing `r_check` gate fields.
- Produces: `classify_r_check_log(path)`, `write_r_check_evidence(result, path)`, and fields `actionable_notes`, `allowed_notes`.

- [ ] Write tests proving a single first-submission NOTE is allowed and every other NOTE fails.
- [ ] Run focused tests and confirm they fail for the missing classifier/contract.
- [ ] Implement exact classification and fail-closed numeric/type validation.
- [ ] Update workflow to classify real check output instead of asserting zero counts.
- [ ] Run focused tests and static YAML/JSON parsing.
- [ ] Commit with `release: classify actionable R check notes`.

### Task 2: Freeze DCC 1.2.0

**Files:**
- Modify: `DESCRIPTION`
- Modify: `NEWS.md`
- Modify: `cran-comments.md`
- Modify: `docs/release-checklist.md`

**Interfaces:**
- Consumes: completed Phase E code at commit `8370eb0`.
- Produces: one version identity, `1.2.0`, for source and evidence.

- [ ] Add a test asserting the candidate is not a development version.
- [ ] Change `DESCRIPTION` from `1.2.0.9000` to `1.2.0` and update release text.
- [ ] Run dependency audit and confirm the existing lock still covers 42 packages.
- [ ] Run full tests, repeated property/fault tests, coverage, build, and check.
- [ ] Record local NOTE classification and artifact SHA-256.
- [ ] Commit with `release: freeze DCC 1.2.0 candidate`.

### Task 3: Push and close the platform matrix

**Files:**
- Evidence only: GitHub Actions artifacts under the workflow run.

**Interfaces:**
- Consumes: frozen `main` candidate.
- Produces: check, coverage, format, installation, and benchmark JSON artifacts.

- [ ] Push local `main` to `origin/main`.
- [ ] Monitor all release workflows through GitHub integration.
- [ ] For each failure, reproduce, add a regression test, fix, verify, commit, and push.
- [ ] Download or record successful artifact identifiers and hashes.

### Task 4: Execute statistician and Agent acceptance

**Files:**
- Modify/Create: `artifacts/acceptance-statistician.json`
- Modify/Create: `artifacts/acceptance-agent.json`
- Modify if defects found: `tools/run-acceptance.R`

**Interfaces:**
- Consumes: eight statistician scenarios and twenty Agent tasks.
- Produces: correctness, caveats, attempts, preview/validation, refusal, and unsafe-execution counts.

- [ ] Execute all statistician scenarios and record non-empty caveats.
- [ ] Execute all Agent tasks against the frozen candidate.
- [ ] Validate at least 90% success within two attempts, zero unsafe executions, and validation/preview before execution.
- [ ] Hash both result files and keep failures blocking.

### Task 5: Create the staff acceptance workbook

**Files:**
- Create: `tests/acceptance/staff/DCC-1.2.0-staff-acceptance.xlsx`
- Modify: `tests/acceptance/staff/README.md`

**Interfaces:**
- Consumes: committed facilitator scenarios and strict DCC staff template.
- Produces: protected instructions, participant records, task outcomes, SUS responses, preview/execute distinction, code-edit/raw-overwrite counts, consent, signature, and summary formulas.

- [ ] Build the workbook with artifact-tool and visible formulas.
- [ ] Inspect key ranges, scan formula errors, and render every sheet.
- [ ] Repair clipping or ambiguous instructions and export one final workbook.
- [ ] Leave participant/signature cells blank and mark the gate facilitator-required.

### Task 6: Assemble final release artifacts and evidence

**Files:**
- Create: final CRAN tarball and internal bundle under `artifacts/`
- Create: `artifacts/release-evidence.json`

**Interfaces:**
- Consumes: frozen source, CI artifacts, benchmark, three-audience evidence, lockfile, and schemas.
- Produces: hashed distributables and the final release verdict.

- [ ] Build the CRAN archive and complete internal repository from the same commit/version.
- [ ] Verify package sources, licenses, repository index, install script, checksums, and `contains_user_data: false`.
- [ ] Assemble evidence using only fresh real artifacts.
- [ ] Run `Rscript tools/verify-release.R artifacts/release-evidence.json`.
- [ ] Stop unless the exact final output is `DCC release evidence: PASS`.
