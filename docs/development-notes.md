# Development Notes

Practical lessons collected while developing DCC. Newest entries first.
These complement, and never override, the repository standard and the
Engineering Handbook.

## 2026-07-12 — execute is linear, or it is not usable

The 1e6-row CI benchmark timed `dcc_execute()` at ~1040s (budget 60s)
while read/detect/chunked stayed at 1-3s. Two O(n^2) paths, both
invisible at the 1e4 scale the unit tests use:

- **Never grow a result with `x[[length(x) + 1]] <-`.** Each append
  copies the whole list, so building a 210k-row audit log that way is
  O(n^2). Pre-size the buffer (`vector("list", nrow(findings))`) and
  write by an incrementing counter; `rbindlist()` the used prefix at
  the end.
- **`list[[character]]` is a linear name scan.** `row_of[[record_id]]`
  on a list with up to 1e6 names is O(n) per finding, O(n^2) overall.
  Hash the ids to positions once with `match(record_id, names(row_of))`
  and index by integer.
- **Hoist constants out of the hot loop.** `dcc_timestamp()` (a
  `format(Sys.time())`) and `packageVersion()` were recomputed per
  change; compute once per run. Timestamps are excluded from
  reproducibility comparisons, so one run-level timestamp is also more
  correct.

Lesson: benchmark at the scale the package claims to serve. Unit tests
at 1e4 rows pass happily through both quadratics.

## 2026-07-12 — v1.0 CRAN-readiness

### Licensing and ownership

- **GPL does not transfer copyright.** DCC uses GPL (>= 2), while copyright
  remains with the funding company. Ownership is expressed in `Authors@R` via
  the `cph` (copyright holder) and `fnd` (funder) roles. The human maintainer
  (`cre`) uses the stable company-domain maintainer address.
- **CRAN and repository metadata must agree.** `DESCRIPTION` declares
  `License: GPL (>= 2)`, the package root contains the GPL version 2 text, and
  `inst/COPYRIGHTS` records company ownership and external dependency
  boundaries. Keep the company's Chinese
  legal name out of the parsed `DESCRIPTION` fields (ASCII only) and
  put the bilingual notice in `LICENSE.md`, which is UTF-8.

### Documentation

- **Every exported function needs a runnable example for CRAN.** Three
  were missing (`dcc_detect_chunked`, `dcc_manifest`, `dcc_rerun`).
  Examples that need a Suggests package guard on
  `requireNamespace("yaml", ...)`, matching the existing detector
  examples.
- **Gate vignette evaluation on Suggests.** The pipeline vignette reads
  YAML rules, so its setup chunk sets `eval = requireNamespace("yaml")`
  and `VignetteBuilder: knitr` / `knitr` + `rmarkdown` are declared, so
  the vignette still builds where a suggested package is absent.

### Changelog hygiene

- **Disambiguate the template's version from the package's.** The repo
  was seeded from the WeianData template whose own release was 1.0.0;
  that CHANGELOG entry was relabelled "Template baseline" so it does not
  collide with the DCC package 1.0.0. Package release notes also live in
  `NEWS.md`, the file CRAN and R users read.

## 2026-07-12 — v0.5 performance backends

### Adaptive chunked backend

- **One entry, two streaming backends.** `dcc_detect_chunked()` keeps
  a single public signature and dispatches on a `backend` argument
  (`auto`/`csv`/`arrow`). `auto` reads the file extension only, so
  backend choice is inspectable and testable without opening the file.
  The chosen backend is stored as a `backend` attribute on the
  findings for provenance and tests.
- **Arrow sidesteps the encoding restriction.** The fread path needs
  an fread-native encoding (UTF-8/latin1); Parquet/Feather are
  columnar UTF-8 with types in the schema, so the Arrow path needs no
  encoding guard and no first-chunk column-type locking -- the schema
  is stable across record batches by construction.
- **Stream Arrow with a batch reader, not a full read.** Use
  `arrow::Scanner$create(ds, batch_size = chunk_size)` +
  `ToRecordBatchReader()` and pull one batch at a time; a plain
  `read_parquet()` would materialise the whole file and defeat the
  bounded-memory goal. `open_dataset()` defaults to Parquet, so pass
  `format = "arrow"` for `.feather`/`.arrow` inputs.
- **Keep new benchmark stages non-gating.** The `chunked_csv` /
  `chunked_arrow` stages are informational (no budget): streaming
  throughput is dominated by the host I/O layer, so a hard threshold
  there would be a flaky gate, not a regression signal.

### CI failures caught on the first real R CMD check

- **Compare finding rows, not finding attributes.** `dcc_findings`
  objects carry object-level attributes (`dcc_data` after
  `dcc_detect()`; `n_rows`/`n_chunks`/`backend` after
  `dcc_detect_chunked()`). `expect_identical()` compares attributes
  too, so a parity test between the chunked and in-memory paths fails
  on the attribute mismatch alone. Strip every non-structural
  attribute (keep only `names`/`row.names`/`class`) in the test's
  normalizer before comparing. `as.data.frame(dt)[order, ]` does *not*
  reliably drop `setattr`-set attributes here, so strip them
  explicitly.
- **ICU misfires to ISO-8859-2 on pure-ASCII data.** The synthetic
  benchmark rows (ids, digits, `A`/`B`/`C`) carry no multibyte signal,
  so `stri_enc_detect` guessed ISO-8859-2 and the fread-native encoding
  guard rejected the file. Same root cause as the v0.1 "auto-detection
  needs signal" lesson. Fix: `dcc_detect_chunked()` now takes an
  `encoding` override (mirroring `dcc_read()`); callers on low-signal
  data pass `encoding = "UTF-8"` instead of relying on detection.
- **The sandbox cannot commit to a mounted `.git`.** The FUSE mount
  denies `unlink` on `.git` files, so once a `git commit` writes
  `index.lock` it can never be removed and every later git call reports
  "another git process seems to be running". Authoritative commits are
  made on the host, not in the sandbox; the sandbox is for editing and
  webR-level verification only.

## 2026-07-11 — v0.1 input layer: first full CI pass

### R CMD check

- **Keep R sources ASCII-only.** Any non-ASCII character in a string
  literal (even a BOM used in a regex) triggers a portability WARNING.
  Use `\uxxxx` escapes in code; non-ASCII is tolerated only in comments,
  but we keep those ASCII too (em dashes become `--`).
- **Every exported object needs an Rd page.** Until roxygen2 is wired
  into CI, `man/*.Rd` and `NAMESPACE` are hand-maintained; each file
  carries a header comment saying so. Keep them in sync with the
  roxygen comments in `R/`.
- **Register data.table NSE columns.** Column names used in `[.data.table`
  expressions must be listed in `utils::globalVariables()` or the check
  NOTE ("no visible binding") fails a warnings-as-errors CI.

### Encoding tests

- **Simplified hanzi are not representable in BIG5.** An encoding
  round-trip fixture must match the target charset: use traditional
  Chinese for BIG5 legs, simplified for GB18030. GB18030 covers all of
  Unicode, so traditional text is safe there too.
- **Charset auto-detection needs signal.** ICU detection on a few short
  fields is unreliable; deterministic tests pass `encoding=` explicitly
  and test auto-detection separately on a longer sample.

### Test design

- **Never put a fixture exactly on a threshold.** A respondent with
  30% missing tested against `prop > 0.3` fails silently (and 3/10 is
  not even exact in floating point). Fixtures should clearly exceed or
  clearly stay under every boundary they exercise.

### Markdown and link checks

- **markdownlint (repo config):** table rows and separator lines need
  spaces around pipes (MD060: `| --- |`, not `|---|`); every ordered
  list restarts at 1 after intervening content (MD029); bold text is
  not a heading — use real heading levels, incrementing one at a time
  (MD036/MD001).
- **Bot-protected domains belong in `.lycheeignore`.** If a cited page
  is valid in a browser but 403s to the checker's user agent regardless
  of URL (e.g. data.unicef.org), exclude the domain rather than drop
  the citation. If only one URL variant is blocked (e.g. a direct PDF),
  prefer linking the landing page instead.
- CRAN short links (`cran.r-project.org/package=x`) 303-redirect; lychee
  reports these as redirects, not errors — no action needed.

### Environment

- The Cowork sandbox (aarch64, no root, restricted egress, 45 s command
  cap, no persistent background processes) cannot run a native R
  toolchain. Verification there is limited to parsing and pure-base
  logic via webR (Node/wasm); the authoritative gate is the R CMD check
  workflow plus a local `devtools::test()` run.

### `dcc_to_irtc()` deferred to a later release (1.1.0 decision)

- Per the v1.1.0 functionality-alignment plan, `dcc_to_irtc()` ships only
  with a stable, end-to-end-tested output contract (`resp`, `pid`,
  `group`, `pweights`, `Q`, anchor information). That contract is not yet
  frozen, so `dcc_to_irtc()` is **Planned**, not implemented: it carries
  no Stable claim and `dcc_capabilities()` reports it as `Planned`. The
  concurrent-calibration layout produced by `dcc_map_forms()` (structural
  `NA` for not-administered items, `is_anchor` carried through) remains
  the supported building block until the IRTC export is specified and
  tested.
