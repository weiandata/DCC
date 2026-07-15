#' Render the statistical report bundle
#'
#' Writes complete analytical tables, provenance, parameters, a methods
#' narrative, and a SHA-256 artifact manifest from one normalized report model.
#' No table is sampled or silently truncated.
#'
#' @param model A [dcc_report_model()] object.
#' @param output_dir Existing or new directory for report files.
#' @param table_format `"parquet"` or `"csv"`.
#' @param html Whether to write `statistical-report.html`.
#' @return Character paths of all files written.
#' @export
dcc_report_statistical <- function(model, output_dir,
                                   table_format = c("parquet", "csv"),
                                   html = TRUE) {
  staff_validate_model(model)
  table_format <- match.arg(table_format)
  if (!is.logical(html) || length(html) != 1L || is.na(html)) {
    dcc_abort("`html` must be TRUE or FALSE.", class = "dcc_report_error")
  }
  if (!is.character(output_dir) || length(output_dir) != 1L ||
      is.na(output_dir) || !nzchar(output_dir)) {
    dcc_abort("`output_dir` must be one directory path.",
              class = "dcc_report_error")
  }
  tables <- statistical_tables(model)
  table_paths <- file.path(
    output_dir, paste0(names(tables), ".", table_format)
  )
  json_paths <- file.path(output_dir, c("provenance.json", "parameters.json"))
  html_path <- if (html) file.path(output_dir, "statistical-report.html") else
    character()
  manifest_path <- file.path(output_dir, "artifact-manifest.json")
  targets <- c(table_paths, json_paths, html_path, manifest_path)
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

  written <- character()
  for (i in seq_along(tables)) {
    report_write_table(tables[[i]], table_paths[i], table_format)
    written <- c(written, table_paths[i])
  }
  provenance_path <- file.path(output_dir, "provenance.json")
  report_write_json(model$provenance, provenance_path)
  written <- c(written, provenance_path)
  parameters_path <- file.path(output_dir, "parameters.json")
  report_write_json(statistical_parameters(model), parameters_path)
  written <- c(written, parameters_path)
  if (html) {
    write_statistical_html(model, names(tables), table_format, html_path)
    written <- c(written, html_path)
  }
  write_artifact_manifest(written, manifest_path)
  written <- c(written, manifest_path)
  normalizePath(written, mustWork = TRUE)
}

statistical_tables <- function(model) {
  list(
    findings = model$findings,
    `audit-log` = model$changes,
    reconciliation = model$reconciliation,
    missingness = model$summaries$missingness,
    distributions = model$summaries$distributions,
    types = model$summaries$types,
    scoring = model$scoring,
    mapping = model$mapping
  )
}

report_write_table <- function(table, path, format) {
  table <- report_utf8_table(table)
  if (format == "csv") {
    data.table::fwrite(
      table, path, sep = ",", quote = "auto", na = "", eol = "\r\n",
      bom = FALSE
    )
  } else {
    arrow::write_parquet(table, path)
  }
  invisible(path)
}

report_utf8_table <- function(table) {
  out <- data.table::copy(data.table::as.data.table(table))
  for (name in names(out)) {
    if (is.character(out[[name]])) {
      data.table::set(out, j = name, value = enc2utf8(out[[name]]))
    }
  }
  out
}

report_write_json <- function(value, path) {
  jsonlite::write_json(
    value, path, auto_unbox = TRUE, dataframe = "rows", null = "null",
    na = "null", pretty = TRUE, digits = NA
  )
  invisible(path)
}

statistical_parameters <- function(model) {
  list(
    contract_version = model$contract$version,
    project = model$project,
    run = model$run,
    input = model$input,
    plan = model$plan,
    counts = model$summaries[c(
      "input_rows", "output_rows", "findings_total", "changes_total",
      "excluded_total", "handled_total", "unhandled_total"
    )],
    sensitivity = model$sensitivity,
    hashes = model$hashes,
    environment = list(
      dcc_version = dcc_version_string(),
      r_version = R.version.string,
      platform = R.version$platform
    )
  )
}

write_statistical_html <- function(model, table_names, table_format, path) {
  links <- paste0(
    "<li><a href='", html_escape(paste0(table_names, ".", table_format)),
    "'>", html_escape(table_names), "</a></li>"
  )
  counts <- data.frame(
    metric = names(model$summaries)[seq_len(7L)],
    value = unlist(model$summaries[seq_len(7L)], use.names = FALSE),
    stringsAsFactors = FALSE
  )
  html <- c(
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<title>DCC statistical report</title>",
    "<style>body{font-family:Arial,sans-serif;max-width:1100px;margin:2em auto;color:#203040;line-height:1.5}h1,h2{color:#1f4e78}table{border-collapse:collapse;width:100%;margin:1em 0}th{background:#1f4e78;color:white}th,td{padding:7px;border-bottom:1px solid #d9e2f3;text-align:left}.note{background:#eaf2f8;border-left:5px solid #5b9bd5;padding:12px}</style></head><body>",
    "<h1>DCC statistical report</h1>",
    paste0("<p><code>run_id</code>: ", html_escape(model$run$run_id),
           " | DCC ", html_escape(model$run$dcc_version),
           " | R version ", html_escape(R.version.string), "</p>"),
    "<h2>Overview</h2>", html_table(counts),
    "<h2>Methods</h2>",
    "<p>All counts and tables are rendered from the validated dcc-report 1.0 normalized model. Renderers do not recompute cleaning decisions.</p>",
    "<h2>Denominators</h2>",
    paste0("<p>Before-cleaning denominator: ", model$summaries$input_rows,
           " rows. After-cleaning denominator: ",
           model$summaries$output_rows, " rows.</p>"),
    "<h2>Missing-value semantics</h2>",
    "<p>Missingness tables distinguish the before and after denominators. Canonical missing-state metadata and applied set_na actions remain available in the provenance and audit artifacts.</p>",
    "<h2>Rules, reconciliation, and provenance</h2>",
    paste0("<p>The ruleset hash is <code>",
           html_escape(model$hashes$ruleset %||% "not available"),
           "</code>. Every finding is joined to its terminal disposition by finding_id.</p>"),
    "<h2>Uncertainty and Caveats</h2>",
    "<p class='note'>These outputs describe deterministic cleaning evidence; they do not estimate sampling uncertainty or choose inferential models. Distribution tables are complete and may contain sensitive values.</p>",
    "<h2>Performance and integrity</h2>",
    paste0("<p>Total recorded stage time: ",
           format(model$performance$total_seconds, trim = TRUE),
           " seconds. Cleaned-data hash: <code>",
           html_escape(model$hashes$cleaned_data), "</code>.</p>"),
    "<h2>Complete tables</h2><ul>", links, "</ul>",
    "<p><a href='provenance.json'>provenance.json</a> | <a href='parameters.json'>parameters.json</a></p>",
    "</body></html>"
  )
  writeLines(html, path, useBytes = TRUE)
  invisible(path)
}

write_artifact_manifest <- function(paths, path) {
  paths <- normalizePath(paths, mustWork = TRUE)
  info <- file.info(paths)
  manifest <- list(
    contract_version = "1.0",
    hash_algorithm = "SHA-256",
    artifacts = data.frame(
      path = basename(paths),
      bytes = as.numeric(info$size),
      sha256 = unname(as.character(tools::sha256sum(paths))),
      stringsAsFactors = FALSE
    )
  )
  report_write_json(manifest, path)
}
