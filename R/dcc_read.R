#' Read a data file into a dcc_data object
#'
#' Compatibility entry point over DCC's registered format adapters. New strict
#' workflows should use dcc_import() with a declared import specification;
#' this function retains automatic text-encoding detection and type inference
#' for existing calls. The raw file is never modified.
#'
#' @param path Path to the input file.
#' @param format auto, a registered format name, or the legacy excel alias.
#' @param encoding auto or an explicit source encoding for text formats.
#' @param ... Compatibility reader options. Protected options remain rejected.
#' @return A dcc_data object with canonical metadata and read provenance.
#' @export
dcc_read <- function(path, format = "auto", encoding = "auto", ...) {
  if (!is.character(path) || length(path) != 1L) {
    dcc_abort("path must be a single file path.", class = "dcc_type_error")
  }
  if (!file.exists(path)) {
    dcc_abort("File not found: ", path, class = "dcc_io_error")
  }
  if (!is.character(format) || length(format) != 1L || is.na(format) ||
      !format %in% c("auto", dcc_read_formats())) {
    dcc_abort("Unsupported format: ", paste(format, collapse = ", "),
              class = "dcc_format_error")
  }

  requested_format <- format
  if (format == "auto") format <- infer_format(path)
  if (format == "excel") {
    extension <- tolower(tools::file_ext(path))
    if (!extension %in% c("xls", "xlsx")) {
      dcc_abort("Legacy format excel requires an .xls or .xlsx source.",
                class = "dcc_format_error")
    }
    format <- extension
  }
  adapter <- dcc_get_adapter(format)
  options <- list(...)
  text_formats <- c("csv", "tsv", "txt", "fwf", "json", "jsonl")
  if (format %in% text_formats) {
    if (identical(encoding, "auto")) {
      options$encoding <- dcc_detect_encoding(path)$encoding
    } else {
      options$encoding <- normalize_encoding(encoding)
    }
  }
  if (format %in% c("xls", "xlsx", "xlsb", "ods")) {
    options$.compatibility <- TRUE
  }

  result <- tryCatch({
    raw <- adapter$reader(path, options)
    validate_adapter_result(raw, format)
    columns <- compatibility_columns(raw$data, raw$metadata)
    spec <- new_import_spec(path, format, options = options,
                            columns = columns)
    dcc_import(path, spec)
  }, error = function(e) {
    if (inherits(e, "dcc_io_error") || inherits(e, "dcc_type_error")) stop(e)
    stop(errorCondition(
      paste0("Could not read ", format, " source: ", conditionMessage(e)),
      class = c("dcc_format_error", "dcc_error"), parent = e
    ))
  })

  legacy_format <- if (format %in% c("xls", "xlsx")) "excel" else format
  result$meta$adapter_format <- format
  result$meta$format <- legacy_format
  record <- result$provenance[[1L]]
  record$stage <- "read"
  record$details <- list(
    source = result$meta$source,
    format = legacy_format,
    adapter_format = format,
    encoding = result$meta$encoding,
    file_hash = result$meta$file_hash,
    n_rows = nrow(result$data),
    n_cols = ncol(result$data),
    l0_findings = nrow(result$read_report$findings),
    compatibility = TRUE,
    requested_format = requested_format
  )
  result$provenance[[1L]] <- record
  result
}

infer_format <- function(path) {
  extension <- tolower(tools::file_ext(path))
  registry <- dcc_format_registry()
  matches <- names(registry)[vapply(
    registry,
    function(adapter) extension %in% adapter$extensions,
    logical(1)
  )]
  if (length(matches) != 1L) {
    detail <- if (length(matches)) {
      paste0("extension is ambiguous (", paste(matches, collapse = ", "), ")")
    } else {
      "extension is not registered"
    }
    dcc_abort("Cannot infer format from extension .", extension, ": ",
              detail, "; pass format explicitly.",
              class = "dcc_format_error")
  }
  matches
}

compatibility_columns <- function(data, metadata = list()) {
  data <- as.data.frame(data, check.names = FALSE, stringsAsFactors = FALSE)
  source_classes <- metadata$source_column_classes %||%
    metadata$column_classes
  if (is.null(source_classes) && length(metadata$variables %||% list())) {
    source_classes <- lapply(metadata$variables, `[[`, "class")
  }
  types <- vapply(names(data), function(name) {
    compatibility_column_type(data[[name]], source_classes[[name]] %||% NULL)
  }, character(1))
  data.frame(
    source_name = names(data),
    name = names(data),
    type = types,
    role = rep.int("other", ncol(data)),
    stringsAsFactors = FALSE
  )
}

compatibility_column_type <- function(column, source_class = NULL) {
  if (any(source_class %in% c("Date"))) return("date")
  if (any(source_class %in% c("POSIXct", "POSIXlt"))) return("datetime")
  if (any(source_class %in% c("integer"))) return("integer")
  if (any(source_class %in% c("numeric", "double", "haven_labelled",
                              "haven_labelled_spss"))) return("double")
  if (any(source_class %in% c("logical"))) return("logical")
  if (inherits(column, "Date")) return("date")
  if (inherits(column, "POSIXt")) return("datetime")
  converted <- utils::type.convert(column, as.is = TRUE,
                                   na.strings = c("", "NA"))
  if (is.integer(converted)) return("integer")
  if (is.numeric(converted)) return("double")
  if (is.logical(converted)) return("logical")
  "character"
}
