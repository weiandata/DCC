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

dcc_format_registry <- function() {
  list(
    csv = planned_adapter("csv", "csv"),
    tsv = planned_adapter("tsv", "tsv"),
    txt = planned_adapter("txt", "txt"),
    fwf = planned_adapter("fwf", "txt"),
    json = planned_adapter("json", "json"),
    jsonl = planned_adapter("jsonl", c("jsonl", "ndjson")),
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
    rds = planned_adapter("rds", "rds")
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
