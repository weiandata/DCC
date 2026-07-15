new_format_adapter <- function(name, extensions, reader, inspector, validator,
                               status, semantics) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name)) {
    dcc_abort("Adapter `name` must be one non-empty string.",
              class = "dcc_format_error")
  }
  if (!is.character(extensions) || !length(extensions) ||
      anyNA(extensions) || any(!nzchar(extensions)) ||
      anyDuplicated(extensions)) {
    dcc_abort("Adapter `extensions` must be unique non-empty strings.",
              class = "dcc_format_error")
  }
  functions <- list(reader = reader, inspector = inspector,
                    validator = validator)
  if (!all(vapply(functions, is.function, logical(1)))) {
    dcc_abort("Adapter reader, inspector, and validator must be functions.",
              class = "dcc_format_error")
  }
  allowed_status <- c("Stable", "Experimental", "Planned", "Unavailable")
  if (!is.character(status) || length(status) != 1L ||
      !status %in% allowed_status) {
    dcc_abort("Adapter `status` must be Stable, Experimental, Planned, or ",
              "Unavailable.", class = "dcc_format_error")
  }
  if (!is.list(semantics)) {
    dcc_abort("Adapter `semantics` must be a list.",
              class = "dcc_format_error")
  }
  structure(
    list(
      name = name,
      extensions = tolower(extensions),
      reader = reader,
      inspector = inspector,
      validator = validator,
      status = status,
      semantics = semantics
    ),
    class = "dcc_format_adapter"
  )
}

planned_adapter <- function(name, extensions) {
  unavailable <- function(...) {
    dcc_abort("Format '", name, "' is not implemented in this build.",
              class = "dcc_format_error")
  }
  new_format_adapter(
    name = name,
    extensions = extensions,
    reader = unavailable,
    inspector = unavailable,
    validator = unavailable,
    status = "Planned",
    semantics = list(
      values = "character-preserving",
      cleaning = FALSE,
      declared_structure = TRUE
    )
  )
}

adapter_delimited <- function(name, extension, separator) {
  reader <- function(path, options = list()) {
    protected <- intersect(names(options), protected_delimited_options())
    if (length(protected)) {
      dcc_abort("Delimited import protected option(s) cannot be overridden: ",
                paste(protected, collapse = ", "), ".",
                class = "dcc_import_error")
    }
    encoding <- options$encoding %||% ""
    if (!nzchar(encoding)) {
      dcc_abort("Delimited imports require an explicit `encoding`.",
                class = "dcc_import_error")
    }
    encoding <- normalize_encoding(encoding)
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    fread_args <- options[setdiff(names(options),
                                  c("encoding", "member", "compression",
                                    "max_uncompressed_bytes"))]
    fread_args <- c(
      list(
        sep = separator,
        colClasses = "character",
        na.strings = NULL,
        check.names = FALSE,
        strip.white = FALSE,
        data.table = FALSE,
        showProgress = FALSE
      ),
      fread_args
    )
    data <- if (encoding %in% c("UTF-8", "latin1")) {
      fread_args$file <- resolved
      fread_args$encoding <- if (encoding == "latin1") "Latin-1" else "UTF-8"
      do.call(data.table::fread, fread_args)
    } else {
      fread_args$input <- read_file_utf8(resolved, encoding)
      do.call(data.table::fread, fread_args)
    }
    list(
      data = as.data.frame(data, stringsAsFactors = FALSE),
      metadata = list(encoding = encoding, separator = separator)
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
        fix = "Choose an existing source file."
      )
    }
    encoding <- spec$options$encoding %||% ""
    if (!nzchar(encoding)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_ENCODING_REQUIRED", "fail", "encoding",
        fix = "Declare the source text encoding."
      )
    }
    protected <- intersect(names(spec$options), protected_delimited_options())
    if (length(protected)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_PROTECTED_OPTION", "fail", protected[1L],
        fix = paste0("Remove protected option(s): ",
                     paste(protected, collapse = ", "), ".")
      )
    }
    new_validation(issues)
  }
  new_format_adapter(
    name = name,
    extensions = extension,
    reader = reader,
    inspector = inspector,
    validator = validator,
    status = "Experimental",
    semantics = list(
      values = "character-preserving",
      encoding = "declared",
      missing = "preserved-before-canonicalization",
      cleaning = FALSE,
      declared_structure = TRUE
    )
  )
}

protected_delimited_options <- function() {
  c("input", "file", "text", "cmd", "sep", "colClasses", "na.strings",
    "col.names", "check.names", "strip.white", "select", "drop",
    "data.table", "showProgress")
}

dcc_format_registry <- function() {
  list(
    csv = adapter_delimited("csv", "csv", ","),
    tsv = adapter_delimited("tsv", "tsv", "\t"),
    txt = adapter_text(),
    fwf = adapter_fwf(),
    json = adapter_json(),
    jsonl = adapter_json(lines = TRUE),
    xls = planned_adapter("xls", "xls"),
    xlsx = planned_adapter("xlsx", "xlsx"),
    xlsb = planned_adapter("xlsb", "xlsb"),
    ods = planned_adapter("ods", "ods"),
    spss = planned_adapter("spss", c("sav", "zsav", "por")),
    stata = planned_adapter("stata", "dta"),
    sas = planned_adapter("sas", "sas7bdat"),
    xpt = planned_adapter("xpt", "xpt"),
    parquet = planned_adapter("parquet", "parquet"),
    feather = planned_adapter("feather", c("feather", "arrow")),
    rds = adapter_rds()
  )
}

dcc_get_adapter <- function(format) {
  if (!is.character(format) || length(format) != 1L || is.na(format) ||
      !nzchar(format)) {
    dcc_abort("`format` must be one non-empty string.",
              class = "dcc_format_error")
  }
  format <- tolower(format)
  registry <- dcc_format_registry()
  if (!format %in% names(registry)) {
    dcc_abort("Unsupported format: ", format, class = "dcc_format_error")
  }
  registry[[format]]
}
