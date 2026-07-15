#' Build a reproducibility manifest for a cleaning run
#'
#' Captures everything needed to re-execute the read -> detect ->
#' execute pipeline and verify byte-identical results: input file path
#' and hash, rule file path and hash, the executed actions, id/default
#' configuration, and content hashes of the cleaned data and the audit
#' log (timestamps excluded). Same raw data + same rule versions =
#' same cleaned data and audit trail (design principle 7).
#'
#' @param x A `dcc_result` from [dcc_execute()], produced from a
#'   [dcc_read()] input and [dcc_detect()] findings (so input and rule
#'   sources are known).
#' @param path Optional path to write the manifest as YAML (requires
#'   the `yaml` package).
#' @return A `dcc_manifest` object (named list), invisibly written to
#'   `path` when given.
#' @export
dcc_manifest <- function(x, path = NULL) {
  stopifnot(inherits(x, "dcc_result"))
  meta <- x$data$meta
  if (is.null(meta$source)) {
    dcc_abort("This result has no input-file metadata; a manifest ",
              "needs a dcc_read() source.", class = "dcc_manifest_error")
  }
  det <- attr(x$findings, "dcc_data", exact = TRUE)
  ruleset_source <- NA_character_
  if (!is.null(det)) {
    recs <- Filter(function(p) p$stage == "detect", det$provenance)
    if (length(recs)) {
      ruleset_source <- recs[[length(recs)]]$details$ruleset
    }
  }
  if (is.na(ruleset_source)) {
    dcc_abort("This result carries no rule-file source; run the ",
              "pipeline via dcc_detect() on a dcc_rules() rule set.",
              class = "dcc_manifest_error")
  }
  manifest <- structure(
    list(
      contract_version = "1.2",
      dcc_version = dcc_version_string(),
      created = dcc_timestamp(),
      input = list(
        source = meta$source,
        file_hash = meta$file_hash,
        format = meta$format,
        encoding = meta$encoding
      ),
      ruleset = list(
        source = ruleset_source,
        hash = x$ruleset_hash
      ),
      id_var = x$id_var,
      default = x$default,
      actions = x$actions,
      output = list(
        data_hash = hash_table(x$data$data),
        audit_hash = hash_table(drop_volatile(x$audit)),
        n_excluded = x$n_excluded
      )
    ),
    class = "dcc_manifest"
  )
  if (!is.null(path)) {
    dcc_require("yaml", "write manifest files")
    yaml::write_yaml(unclass(manifest), path)
  }
  invisible(manifest)
}

#' Re-run a cleaning pipeline from its manifest and verify the output
#'
#' Reads the raw input again, verifies its hash, reloads the rule file
#' and verifies its hash, re-runs detect and execute with the recorded
#' actions, and compares the cleaned data and the audit log (excluding
#' timestamps) against the manifest hashes.
#'
#' @param manifest A `dcc_manifest`, a `dcc_result` (a manifest is
#'   built from it first), or a path to a manifest YAML file.
#' @return A `dcc_rerun` object: list with `reproduced` (logical),
#'   `data_match`, `audit_match`, and the re-run `result`. An input or
#'   rule file whose hash no longer matches raises a typed error --
#'   changed inputs make reproduction claims meaningless.
#' @export
dcc_rerun <- function(manifest) {
  if (inherits(manifest, "dcc_result")) {
    manifest <- dcc_manifest(manifest)
  } else if (is.character(manifest) && length(manifest) == 1L) {
    dcc_require("yaml", "read manifest files")
    if (!file.exists(manifest)) {
      dcc_abort("Manifest file not found: ", manifest,
                class = "dcc_io_error")
    }
    manifest <- structure(yaml::read_yaml(manifest),
                          class = "dcc_manifest")
  }
  if (!inherits(manifest, "dcc_manifest")) {
    dcc_abort("`manifest` must be a dcc_manifest, dcc_result, or a ",
              "manifest file path.", class = "dcc_type_error")
  }

  inp <- manifest$input
  if (!file.exists(inp$source)) {
    dcc_abort("Input file missing: ", inp$source,
              class = "dcc_rerun_error")
  }
  if (!identical(unname(tools::md5sum(inp$source)), inp$file_hash)) {
    dcc_abort("Input file hash mismatch for ", inp$source,
              "; the raw data changed since the original run.",
              class = "dcc_rerun_error")
  }
  if (!file.exists(manifest$ruleset$source)) {
    dcc_abort("Rule file missing: ", manifest$ruleset$source,
              class = "dcc_rerun_error")
  }
  rules <- dcc_rules(manifest$ruleset$source)
  if (!identical(rules$hash, manifest$ruleset$hash)) {
    dcc_abort("Rule file hash mismatch for ", manifest$ruleset$source,
              "; the rules changed since the original run.",
              class = "dcc_rerun_error")
  }

  x <- dcc_read(inp$source, format = inp$format,
                encoding = if (identical(inp$encoding, "native")) {
                  "auto"
                } else {
                  inp$encoding
                })
  findings <- dcc_detect(x, rules, id_var = manifest$id_var)
  result <- dcc_execute(x, findings, actions = manifest$actions,
                        id_var = manifest$id_var,
                        default = manifest$default)

  data_match <- identical(hash_table(result$data$data),
                          manifest$output$data_hash)
  audit_match <- identical(hash_table(drop_volatile(result$audit)),
                           manifest$output$audit_hash)
  structure(
    list(
      reproduced = data_match && audit_match,
      data_match = data_match,
      audit_match = audit_match,
      result = result
    ),
    class = "dcc_rerun"
  )
}

#' @export
print.dcc_rerun <- function(x, ...) {
  cat("<dcc_rerun>\n")
  cat(sprintf("  reproduced: %s (data %s, audit %s)\n",
              x$reproduced, x$data_match, x$audit_match))
  invisible(x)
}

# Content hash of a table: canonical CSV bytes -> MD5.
hash_table <- function(dt) {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  data.table::fwrite(data.table::as.data.table(dt), tmp)
  unname(tools::md5sum(tmp))
}

# Remove run-dependent columns before hashing the audit log.
drop_volatile <- function(log) {
  keep <- setdiff(names(log), "timestamp")
  log[, keep, with = FALSE]
}
