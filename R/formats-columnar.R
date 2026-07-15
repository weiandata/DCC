adapter_arrow <- function(name) {
  extensions <- if (name == "parquet") "parquet" else c("feather", "arrow")
  reader <- function(path, options = list()) {
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    table <- tryCatch(
      if (name == "parquet") {
        arrow::read_parquet(resolved, as_data_frame = FALSE)
      } else {
        arrow::read_feather(resolved, as_data_frame = FALSE)
      },
      error = function(e) {
        dcc_abort("Could not read ", toupper(name), " source: ",
                  conditionMessage(e), class = "dcc_import_error")
      }
    )
    data <- as.data.frame(table)
    if (any(vapply(data, is.list, logical(1)))) {
      dcc_abort(toupper(name), " nested/list columns are not supported.",
                class = "dcc_import_error")
    }
    column_names <- names(data)
    if (anyNA(column_names) || any(!nzchar(column_names)) ||
        anyDuplicated(column_names)) {
      dcc_abort(toupper(name),
                " source columns must have unique non-empty names.",
                class = "dcc_import_error")
    }
    list(
      data = data,
      metadata = list(backend = "arrow", schema = table$schema$ToString(),
                      column_classes = lapply(data, class))
    )
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  validator <- function(path, spec) {
    issues <- list()
    if (!file.exists(path)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_SOURCE_MISSING", "fail", "source",
        fix = "Choose an existing columnar data file."
      )
    }
    allowed <- c("member", "compression", "max_uncompressed_bytes")
    unknown <- setdiff(names(spec$options), allowed)
    if (length(unknown)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_UNKNOWN_OPTION", "fail", unknown[1L],
        fix = paste0("Remove unsupported columnar option(s): ",
                     paste(unknown, collapse = ", "), ".")
      )
    }
    new_validation(issues)
  }
  new_format_adapter(
    name, extensions, reader, inspector, validator, "Experimental",
    list(backend = "arrow", minimum_version = NA_character_,
         schema = "preserved", values = "native Arrow scalars",
         nested_values = "rejected", cleaning = FALSE,
         declared_structure = TRUE)
  )
}
