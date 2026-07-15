#' Render the machine report bundle
#'
#' Writes deterministic JSON and JSONL artifacts plus the versioned schemas
#' needed by an AI agent or external system to validate them.
#'
#' @param model A [dcc_report_model()] object.
#' @param output_dir Existing or new directory for machine artifacts.
#' @return Paths to the eight machine files and the `schemas` directory.
#' @export
dcc_report_machine <- function(model, output_dir) {
  staff_validate_model(model)
  if (!is.character(output_dir) || length(output_dir) != 1L ||
      is.na(output_dir) || !nzchar(output_dir)) {
    dcc_abort("`output_dir` must be one directory path.",
              class = "dcc_report_error")
  }
  names <- c(
    "run.json", "validation.json", "summary.json", "findings.jsonl",
    "audit-log.jsonl", "reconciliation.jsonl", "provenance.json",
    "manifest.json", "schemas"
  )
  targets <- file.path(output_dir, names)
  collisions <- targets[file.exists(targets)]
  if (length(collisions)) {
    dcc_abort("Report output already exists: ", collisions[1L],
              class = "dcc_report_error")
  }
  if (!dir.exists(output_dir) &&
      !dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)) {
    dcc_abort("Could not create report directory: ", output_dir,
              class = "dcc_report_error")
  }
  schema_dir <- file.path(output_dir, "schemas")
  if (!dir.create(schema_dir, showWarnings = FALSE)) {
    dcc_abort("Could not create machine schema directory.",
              class = "dcc_report_error")
  }

  run_id <- as.character(model$run$run_id)
  run <- list(
    contract_version = "1.0",
    run_id = run_id,
    status = as.character(model$run$status),
    mode = as.character(model$run$mode),
    dcc_version = as.character(model$run$dcc_version),
    generated_at = machine_utc_timestamp(Sys.time())
  )
  validation <- list(
    contract_version = "1.0", run_id = run_id,
    issues = model$validation
  )
  summary <- machine_summary_from_model(model)
  summary <- c(list(contract_version = "1.0", run_id = run_id), summary)
  findings <- machine_add_context(model$findings, run_id)
  audit <- machine_add_context(model$changes, run_id)
  audit <- machine_normalize_time_columns(audit, "timestamp")
  reconciliation <- machine_add_context(model$reconciliation, run_id)
  provenance_records <- machine_add_context(model$provenance, run_id)
  provenance_records <- machine_normalize_time_columns(
    provenance_records, c("started_at", "ended_at")
  )
  provenance_records <- machine_normalize_object_columns(
    provenance_records, c("hashes", "counts", "details")
  )
  provenance <- list(
    contract_version = "1.0", run_id = run_id,
    records = provenance_records
  )

  paths <- stats::setNames(file.path(output_dir, names[seq_len(7L)]),
                           names[seq_len(7L)])
  report_write_json(run, paths[["run.json"]])
  report_write_json(validation, paths[["validation.json"]])
  report_write_json(summary, paths[["summary.json"]])
  machine_write_jsonl(findings, paths[["findings.jsonl"]])
  machine_write_jsonl(audit, paths[["audit-log.jsonl"]])
  machine_write_jsonl(reconciliation, paths[["reconciliation.jsonl"]])
  report_write_json(provenance, paths[["provenance.json"]])

  schema_paths <- machine_copy_schemas(schema_dir)
  manifest_path <- file.path(output_dir, "manifest.json")
  machine_write_manifest(
    c(unname(paths), schema_paths), manifest_path, output_dir, run_id,
    basename(schema_paths)
  )
  machine_validate_bundle(output_dir)
  normalizePath(c(unname(paths), manifest_path, schema_dir), mustWork = TRUE)
}

#' Create a bounded structured result summary for AI agents
#'
#' @param result A `dcc_result` returned by [dcc_execute()].
#' @param detail `"compact"` returns at most 20 finding rows without raw
#'   evidence; `"full"` adds reconciliation, provenance, and hashes.
#' @return A named structured list containing stable action codes.
#' @export
dcc_result_summary <- function(result, detail = c("compact", "full")) {
  if (!inherits(result, "dcc_result")) {
    dcc_abort("`result` must be a dcc_result.", class = "dcc_type_error")
  }
  detail <- match.arg(detail)
  model <- dcc_report_model(result)
  compact <- machine_summary_from_model(model)
  if (detail == "compact") return(compact)
  c(compact, list(
    reconciliation = model$reconciliation,
    provenance = model$provenance,
    hashes = model$hashes
  ))
}

machine_summary_from_model <- function(model) {
  reconciliation <- data.table::as.data.table(model$reconciliation)
  status <- if (nrow(reconciliation) && any(reconciliation$status == "failed")) {
    "failed"
  } else if (model$summaries$unhandled_total > 0L ||
             (nrow(reconciliation) && any(reconciliation$severity == "fail"))) {
    "needs_review"
  } else {
    "success"
  }
  if (nrow(reconciliation)) {
    rank <- match(reconciliation$severity, c("fail", "warn", "info"))
    rank[is.na(rank)] <- 4L
    ordered <- reconciliation[order(
      rank, detector_id, variable, record_id, finding_id,
      na.last = TRUE
    )]
    columns <- intersect(
      c("finding_id", "record_id", "variable", "code", "detector_id",
        "severity", "status"), names(ordered)
    )
    top <- as.data.frame(utils::head(ordered[, columns, with = FALSE], 20L),
                         stringsAsFactors = FALSE)
  } else {
    top <- data.frame(
      finding_id = character(), record_id = character(), variable = character(),
      code = character(), detector_id = character(), severity = character(),
      status = character(), stringsAsFactors = FALSE
    )
  }
  actions <- character()
  if (model$summaries$unhandled_total > 0L) {
    actions <- c(actions, "REVIEW_UNHANDLED_FINDINGS")
  }
  if (nrow(reconciliation) && any(reconciliation$status == "failed")) {
    actions <- c(actions, "RESOLVE_FAILED_ACTIONS")
  }
  if (nrow(reconciliation) && any(reconciliation$severity == "fail")) {
    actions <- c(actions, "REVIEW_FAIL_SEVERITY_FINDINGS")
  }
  if (model$summaries$excluded_total > 0L) {
    actions <- c(actions, "VERIFY_EXCLUSIONS")
  }
  if (!length(actions)) actions <- "NO_ACTION_REQUIRED"
  list(
    status = status,
    counts = model$summaries[c(
      "input_rows", "output_rows", "findings_total", "changes_total",
      "excluded_total", "handled_total", "unhandled_total"
    )],
    top_findings = top,
    artifacts = as.character(model$outputs$path %||% character()),
    next_actions = unique(actions)
  )
}

machine_add_context <- function(table, run_id) {
  table <- as.data.frame(table, stringsAsFactors = FALSE)
  data.frame(
    contract_version = rep.int("1.0", nrow(table)),
    run_id = rep.int(run_id, nrow(table)),
    table,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

machine_utc_timestamp <- function(x) {
  format(as.POSIXct(x, tz = "UTC"), tz = "UTC",
         format = "%Y-%m-%dT%H:%M:%OS3Z")
}

machine_normalize_time_columns <- function(table, columns) {
  for (column in intersect(columns, names(table))) {
    raw <- as.character(table[[column]])
    parsed <- suppressWarnings(as.POSIXct(
      raw, format = "%Y-%m-%dT%H:%M:%OS%z", tz = "UTC"
    ))
    ok <- !is.na(parsed)
    raw[ok] <- format(parsed[ok], tz = "UTC",
                      format = "%Y-%m-%dT%H:%M:%OS3Z")
    table[[column]] <- raw
  }
  table
}

machine_normalize_object_columns <- function(table, columns) {
  for (column in intersect(columns, names(table))) {
    table[[column]] <- lapply(table[[column]], function(value) {
      if (is.list(value) && !length(value) && is.null(names(value))) {
        names(value) <- character()
      }
      value
    })
  }
  table
}

machine_write_jsonl <- function(table, path) {
  table <- as.data.frame(table, stringsAsFactors = FALSE)
  lines <- if (nrow(table)) vapply(seq_len(nrow(table)), function(i) {
    jsonlite::toJSON(
      as.list(table[i, , drop = FALSE]), auto_unbox = TRUE,
      dataframe = "rows", null = "null", na = "null", digits = NA
    )
  }, character(1)) else character()
  writeLines(enc2utf8(lines), path, useBytes = TRUE)
  invisible(path)
}

machine_schema_files <- function() {
  c(
    "run.schema.json" = "run",
    "validation.schema.json" = "validation",
    "summary.schema.json" = "summary",
    "finding.schema.json" = "finding",
    "audit-record.schema.json" = "audit_record",
    "reconciliation.schema.json" = "reconciliation",
    "provenance.schema.json" = "machine_provenance",
    "artifact-manifest.schema.json" = "artifact_manifest"
  )
}

machine_copy_schemas <- function(directory) {
  files <- machine_schema_files()
  destinations <- file.path(directory, names(files))
  copied <- vapply(seq_along(files), function(i) {
    file.copy(dcc_schema(unname(files[i]), as = "path"), destinations[i],
              overwrite = FALSE)
  }, logical(1))
  if (!all(copied)) {
    dcc_abort("Could not copy every machine schema.",
              class = "dcc_report_error")
  }
  destinations
}

machine_relative_paths <- function(paths, root) {
  root <- normalizePath(root, mustWork = TRUE)
  paths <- normalizePath(paths, mustWork = TRUE)
  prefix <- paste0(root, .Platform$file.sep)
  relative <- ifelse(startsWith(paths, prefix),
                     substring(paths, nchar(prefix) + 1L), basename(paths))
  gsub("\\\\", "/", relative)
}

machine_write_manifest <- function(paths, path, root, run_id, schemas) {
  paths <- normalizePath(paths, mustWork = TRUE)
  info <- file.info(paths)
  manifest <- list(
    contract_version = "1.0",
    run_id = run_id,
    status = "success",
    hash_algorithm = "SHA-256",
    artifacts = data.frame(
      path = machine_relative_paths(paths, root),
      bytes = as.numeric(info$size),
      sha256 = unname(as.character(tools::sha256sum(paths))),
      stringsAsFactors = FALSE
    ),
    schemas = as.character(schemas)
  )
  report_write_json(manifest, path)
}

machine_validate_bundle <- function(output_dir) {
  json <- c(
    run = "run.json", validation = "validation.json",
    summary = "summary.json", machine_provenance = "provenance.json",
    artifact_manifest = "manifest.json"
  )
  valid_json <- vapply(names(json), function(schema) {
    dcc_validate_json(file.path(output_dir, json[[schema]]), schema)
  }, logical(1))
  jsonl <- c(
    finding = "findings.jsonl", audit_record = "audit-log.jsonl",
    reconciliation = "reconciliation.jsonl"
  )
  valid_jsonl <- vapply(names(jsonl), function(schema) {
    dcc_validate_jsonl(file.path(output_dir, jsonl[[schema]]), schema)
  }, logical(1))
  if (!all(valid_json) || !all(valid_jsonl)) {
    dcc_abort("Generated machine report failed its published schema.",
              class = "dcc_report_error")
  }
  invisible(TRUE)
}

#' Validate a JSON artifact against a published DCC schema
#'
#' Uses DCC's dependency-free JSON Schema subset validator. The published
#' schema remains suitable for full external JSON Schema validators.
#'
#' @param path Existing `.json` file.
#' @param schema A schema name accepted by [dcc_schema()].
#' @return `TRUE` when valid and `FALSE` for malformed or invalid JSON.
#' @export
dcc_validate_json <- function(path, schema) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    return(FALSE)
  }
  value <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(value)) return(FALSE)
  definition <- tryCatch(dcc_schema(schema), error = function(e) NULL)
  !is.null(definition) && json_schema_subset_valid(value, definition)
}

#' Validate a JSON Lines artifact against a published DCC row schema
#'
#' @inheritParams dcc_validate_json
#' @return `TRUE` when every non-empty line is valid JSON matching `schema`.
#' @export
dcc_validate_jsonl <- function(path, schema) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    return(FALSE)
  }
  definition <- tryCatch(dcc_schema(schema), error = function(e) NULL)
  if (is.null(definition)) return(FALSE)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!length(lines)) return(TRUE)
  all(vapply(lines, function(line) {
    value <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE),
                      error = function(e) NULL)
    !is.null(value) && json_schema_subset_valid(value, definition)
  }, logical(1)))
}

json_schema_subset_valid <- function(value, schema) {
  if (!is.null(schema$type)) {
    types <- as.character(schema$type)
    if (!any(vapply(types, json_value_has_type, logical(1), value = value))) {
      return(FALSE)
    }
  }
  if (!is.null(schema$const) && !identical(value, schema$const)) return(FALSE)
  if (!is.null(schema$enum)) {
    allowed <- as.list(schema$enum)
    if (!any(vapply(allowed, function(x) identical(value, x), logical(1)))) {
      return(FALSE)
    }
  }
  if (!is.null(schema$pattern) && is.character(value) &&
      !grepl(schema$pattern, value, perl = TRUE)) return(FALSE)
  if (!is.null(schema$minimum) && is.numeric(value) &&
      value < schema$minimum) return(FALSE)

  if (json_value_has_type(value, "object")) {
    fields <- names(value)
    required <- as.character(schema$required %||% character())
    if (length(setdiff(required, fields))) return(FALSE)
    properties <- schema$properties %||% list()
    if (identical(schema$additionalProperties, FALSE) &&
        length(setdiff(fields, names(properties)))) return(FALSE)
    common <- intersect(fields, names(properties))
    for (field in common) {
      if (!json_schema_subset_valid(value[[field]], properties[[field]])) {
        return(FALSE)
      }
    }
  }
  if (json_value_has_type(value, "array")) {
    if (!is.null(schema$maxItems) && length(value) > schema$maxItems) {
      return(FALSE)
    }
    if (!is.null(schema$items) && length(value) &&
        !all(vapply(value, json_schema_subset_valid, logical(1),
                    schema = schema$items))) return(FALSE)
  }
  TRUE
}

json_value_has_type <- function(value, type) {
  switch(
    type,
    object = is.list(value) && !is.null(names(value)),
    array = is.list(value) && is.null(names(value)),
    string = is.character(value) && length(value) == 1L,
    integer = is.numeric(value) && length(value) == 1L &&
      is.finite(value) && value == as.integer(value),
    number = is.numeric(value) && length(value) == 1L && is.finite(value),
    boolean = is.logical(value) && length(value) == 1L && !is.na(value),
    null = is.null(value),
    FALSE
  )
}
