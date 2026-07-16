# DCC 1.2.0 Release Candidate Evidence Design

## Purpose

Turn the completed Phase E implementation into a release candidate whose
claims are backed by fresh, hashed evidence. The candidate serves survey
staff, statisticians, and AI Agents without weakening DCC's dependency or
safety constraints.

## Decisions

### NOTE policy

The release gate requires zero actionable `R CMD check` NOTEs. The only
permitted NOTE is the unavoidable CRAN incoming-check classification for a
first submission, represented by the stable code `cran_new_submission`.

Evidence records:

- `notes`: total NOTE count reported by the check;
- `actionable_notes`: count not covered by the exact allowlist;
- `allowed_notes`: unique stable codes assigned by DCC's classifier.

The gate passes this part only when errors and warnings are zero,
`actionable_notes` is zero, `notes` equals `length(allowed_notes)`, and every
code is exactly `cran_new_submission`. Unknown, duplicate, ambiguous, or
unparseable NOTE output fails closed. HTML Tidy, development-version, future
timestamp, dependency, documentation, and platform NOTEs are actionable.

### Candidate identity

The candidate version is `1.2.0`. `DESCRIPTION`, CRAN source archive, internal
offline bundle, capability hash, and release evidence must all identify that
version. The frozen candidate commit is pushed to `main`; distributed files
are identified by SHA-256.

### Evidence sources

GitHub Actions produces Linux, macOS, Windows, and R-devel evidence for checks,
formats, installation, coverage, and performance. Local evidence is useful for
diagnosis but cannot replace a required platform artifact.

Statistician and Agent scenarios are executed from their committed contracts
and produce machine-readable results. Staff evidence is collected in a strict
Excel workbook from at least one real participant when the advisory study is
conducted. DCC prepares and validates the workbook but never fabricates names,
signatures, scores, or completion.

### Final gate

An assembled `release-evidence.json` must satisfy the closed JSON schema and
`tools/verify-release.R`. Missing required external evidence remains a blocking
failure, except that staff study outcomes are explicitly advisory. The verifier
never converts an incomplete CI matrix into a pass.

## Considered alternatives

1. **Exact coded allowlist (selected).** Auditable, deterministic, and safe for
   Agent-generated evidence.
2. **Free-text regex allowlist.** Rejected because broad patterns can hide an
   actionable NOTE that happens to share words with the first-submission NOTE.
3. **Absolute zero NOTEs.** Rejected because it makes a genuine first CRAN
   submission impossible while adding no safety value.

## Verification

- Red/green unit tests for allowed, actionable, malformed, and mismatched NOTE
  evidence.
- Fixture tests for the check-log classifier.
- Full zero-failure/warning/skip release tests and repeated property/fault tests.
- Coverage gate: overall at least 90%, all seven critical areas at least 95%.
- Source build and `R CMD check --as-cran` on the frozen candidate.
- Three-platform CI artifacts and final evidence-verifier PASS.

## Authorization and external boundaries

The company legal representative authorized candidate preparation, NOTE-policy
change, push to `main`, CI follow-through, statistician/Agent execution, and
staff acceptance-package creation. Real staff participation and signatures are
advisory and do not block release; CRAN credentials and CRAN's final decision
remain external facts and are never synthesized.
