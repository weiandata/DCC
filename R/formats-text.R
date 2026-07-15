adapter_text <- function() {
  reader <- function(path, options = list()) {
    delimiter <- options$delimiter %||% ""
    if (!is.character(delimiter) || length(delimiter) != 1L ||
        nchar(delimiter) != 1L) {
      dcc_abort("TXT import requires one declared `delimiter` character.",
                class = "dcc_import_error")
    }
    inner <- adapter_delimited("txt", "txt", delimiter)
    inner$reader(path, options[setdiff(names(options), "delimiter")])
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  validator <- function(path, spec) {
    delimiter <- spec$options$delimiter %||% ""
    if (!is.character(delimiter) || length(delimiter) != 1L ||
        nchar(delimiter) != 1L) {
      return(new_validation(list(val_issue(
        "IMPORT_DELIMITER_REQUIRED", "fail", "delimiter",
        fix = "Declare one delimiter character for TXT input."
      ))))
    }
    inner <- adapter_delimited("txt", "txt", delimiter)
    inner$validator(path, spec)
  }
  new_format_adapter(
    "txt", "txt", reader, inspector, validator, "Experimental",
    list(backend = "data.table", minimum_version = "1.14.0",
         values = "character-preserving", delimiter = "declared",
         encoding = "declared", cleaning = FALSE,
         declared_structure = TRUE)
  )
}

adapter_fwf <- function() {
  reader <- function(path, options = list()) {
    widths <- options$widths
    col_names <- options$col_names
    encoding <- options$encoding %||% ""
    if (!is.numeric(widths) || !length(widths) || anyNA(widths) ||
        any(widths == 0)) {
      dcc_abort("FWF import requires non-zero declared `widths`.",
                class = "dcc_import_error")
    }
    if (!is.character(col_names) || length(col_names) != length(widths) ||
        anyNA(col_names) || any(!nzchar(col_names)) ||
        anyDuplicated(col_names)) {
      dcc_abort("FWF import requires one unique `col_names` value per width.",
                class = "dcc_import_error")
    }
    if (!nzchar(encoding)) {
      dcc_abort("FWF import requires an explicit `encoding`.",
                class = "dcc_import_error")
    }
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    text <- read_file_utf8(resolved, normalize_encoding(encoding))
    text <- sub("\\r?\\n$", "", text)
    con <- textConnection(text, open = "r", local = TRUE)
    on.exit(close(con), add = TRUE)
    data <- utils::read.fwf(
      con, widths = widths, header = FALSE, col.names = col_names,
      colClasses = "character", strip.white = FALSE,
      blank.lines.skip = FALSE, stringsAsFactors = FALSE,
      comment.char = ""
    )
    list(data = data,
         metadata = list(encoding = normalize_encoding(encoding),
                         widths = widths))
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  validator <- function(path, spec) {
    issues <- list()
    if (is.null(spec$options$widths)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_WIDTHS_REQUIRED", "fail", "widths",
        fix = "Declare fixed field widths."
      )
    }
    if (is.null(spec$options$col_names)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_COLUMN_NAMES_REQUIRED", "fail", "col_names",
        fix = "Declare fixed-width source column names."
      )
    }
    if (!nzchar(spec$options$encoding %||% "")) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_ENCODING_REQUIRED", "fail", "encoding",
        fix = "Declare the source text encoding."
      )
    }
    new_validation(issues)
  }
  new_format_adapter(
    "fwf", "txt", reader, inspector, validator, "Experimental",
    list(backend = "utils", minimum_version = NA_character_,
         values = "character-preserving", widths = "declared",
         encoding = "declared", cleaning = FALSE,
         declared_structure = TRUE)
  )
}

adapter_json <- function(lines = FALSE) {
  name <- if (lines) "jsonl" else "json"
  extensions <- if (lines) c("jsonl", "ndjson") else "json"
  reader <- function(path, options = list()) {
    encoding <- options$encoding %||% ""
    if (!nzchar(encoding)) {
      dcc_abort(toupper(name), " import requires an explicit `encoding`.",
                class = "dcc_import_error")
    }
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    text <- read_file_utf8(resolved, normalize_encoding(encoding))
    data <- if (lines) {
      con <- textConnection(text, open = "r", local = TRUE)
      on.exit(close(con), add = TRUE)
      jsonlite::stream_in(con, verbose = FALSE, simplifyVector = TRUE)
    } else {
      jsonlite::fromJSON(text, simplifyDataFrame = TRUE,
                         simplifyMatrix = FALSE)
    }
    data <- rectangular_character_data(data, toupper(name))
    list(data = data,
         metadata = list(encoding = normalize_encoding(encoding),
                         records = if (lines) "json-lines" else "array"))
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
        fix = "Choose an existing source file."
      )
    }
    if (!nzchar(spec$options$encoding %||% "")) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_ENCODING_REQUIRED", "fail", "encoding",
        fix = "Declare the source text encoding."
      )
    }
    new_validation(issues)
  }
  new_format_adapter(
    name, extensions, reader, inspector, validator, "Experimental",
    list(backend = "jsonlite", minimum_version = NA_character_,
         values = "JSON scalar to character", encoding = "declared",
         nested_values = "rejected", cleaning = FALSE,
         declared_structure = TRUE)
  )
}

rectangular_character_data <- function(data, format) {
  if (!is.data.frame(data)) {
    dcc_abort(format, " input must be a rectangular array of records.",
              class = "dcc_import_error")
  }
  nested <- vapply(data, is.list, logical(1))
  if (any(nested)) {
    dcc_abort(format, " columns must contain scalar values; nested column(s): ",
              paste(names(data)[nested], collapse = ", "), ".",
              class = "dcc_import_error")
  }
  out <- lapply(data, as.character)
  as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
}

adapter_rds <- function() {
  reader <- function(path, options = list()) {
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    data <- readRDS(resolved)
    if (!is.data.frame(data)) {
      dcc_abort("RDS import requires an object inheriting from data.frame.",
                class = "dcc_import_error")
    }
    classes <- lapply(data, class)
    list(data = as.data.frame(data, check.names = FALSE,
                              stringsAsFactors = FALSE),
         metadata = list(column_classes = classes,
                         trusted_serialized_source_required = TRUE))
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  validator <- function(path, spec) {
    if (!file.exists(path)) {
      return(new_validation(list(val_issue(
        "IMPORT_SOURCE_MISSING", "fail", "source",
        fix = "Choose an existing source file."
      ))))
    }
    empty_validation()
  }
  new_format_adapter(
    "rds", "rds", reader, inspector, validator, "Experimental",
    list(backend = "base", minimum_version = NA_character_,
         values = "native R scalars", trust = "trusted sources only",
         cleaning = FALSE, declared_structure = TRUE)
  )
}
