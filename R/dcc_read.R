#' Read a data file into a dcc_data object
#'
#' The DCC input layer. Reads delimited text (CSV/TSV), Excel, SPSS,
#' Stata, SAS, Parquet, Feather, and rectangular JSON files into a
#' [dcc_data()] container. Text encodings are auto-detected
#' ([dcc_detect_encoding()]) with explicit override; UTF-8, GB18030/GBK,
#' BIG5, and latin1 are first-class. On read, level-0 structural
#' diagnostics ([dcc_l0_diagnose()]) run automatically and the resulting
#' read report is attached to the returned object. Reading never silently
#' coerces: type decisions are recorded in the read report.
#'
#' @param path Path to the input file.
#' @param format One of `"auto"` (default; inferred from the file
#'   extension), `"csv"`, `"tsv"`, `"excel"`, `"spss"`, `"stata"`,
#'   `"sas"`, `"parquet"`, `"feather"`, `"json"`.
#' @param encoding `"auto"` (default) or an explicit source encoding for
#'   text formats (e.g. `"UTF-8"`, `"GB18030"`, `"BIG5"`, `"latin1"`).
#'   Ignored for binary formats, which define their own encoding.
#' @param ... Additional arguments passed to the underlying reader
#'   (`data.table::fread`, `readxl::read_excel`, `haven::read_sav`, ...).
#' @return A [dcc_data()] object with `meta`, a `read_report`, and a
#'   provenance chain whose first record is the read operation.
#' @export
dcc_read <- function(path, format = "auto", encoding = "auto", ...) {
  if (!is.character(path) || length(path) != 1L) {
    dcc_abort("`path` must be a single file path.", class = "dcc_type_error")
  }
  if (!file.exists(path)) {
    dcc_abort("File not found: ", path, class = "dcc_io_error")
  }

  format <- match.arg(format, c("auto", dcc_read_formats()))
  if (format == "auto") {
    format <- infer_format(path)
  }

  enc_info <- list(encoding = NA_character_, confidence = NA_real_)
  is_text <- format %in% c("csv", "tsv", "json")
  if (is_text) {
    if (identical(encoding, "auto")) {
      enc_info <- dcc_detect_encoding(path)
    } else {
      enc_info <- list(encoding = normalize_encoding(encoding),
                       confidence = NA_real_)
    }
  }

  dt <- switch(format,
    csv     = read_delim_dcc(path, sep = ",", enc_info$encoding, ...),
    tsv     = read_delim_dcc(path, sep = "\t", enc_info$encoding, ...),
    excel   = read_excel_dcc(path, ...),
    spss    = read_haven_dcc(path, "sav", ...),
    stata   = read_haven_dcc(path, "dta", ...),
    sas     = read_haven_dcc(path, "sas7bdat", ...),
    parquet = read_arrow_dcc(path, "parquet", ...),
    feather = read_arrow_dcc(path, "feather", ...),
    json    = read_json_dcc(path, enc_info$encoding, ...)
  )

  meta <- list(
    source = normalizePath(path),
    format = format,
    encoding = if (is_text) enc_info$encoding else "native",
    encoding_confidence = enc_info$confidence,
    file_hash = unname(tools::md5sum(path)),
    file_size = file.size(path),
    read_time = dcc_timestamp(),
    dcc_version = dcc_version_string()
  )

  report <- dcc_l0_diagnose(dt, meta)

  out <- dcc_data(
    data = dt,
    meta = meta,
    read_report = report,
    provenance = list(new_provenance_record(
      stage = "read",
      details = list(
        source = meta$source,
        format = format,
        encoding = meta$encoding,
        file_hash = meta$file_hash,
        n_rows = nrow(dt),
        n_cols = ncol(dt),
        l0_findings = nrow(report$findings)
      ),
      hashes = list(input = meta$file_hash),
      counts = list(rows = nrow(dt), columns = ncol(dt),
                    l0_findings = nrow(report$findings))
    ))
  )
  out
}

infer_format <- function(path) {
  ext <- tolower(tools::file_ext(path))
  fmt <- switch(ext,
    csv = "csv",
    tsv = "tsv",
    txt = "tsv",
    xlsx = "excel",
    xls = "excel",
    sav = "spss",
    zsav = "spss",
    dta = "stata",
    sas7bdat = "sas",
    parquet = "parquet",
    feather = "feather",
    arrow = "feather",
    json = "json",
    NULL
  )
  if (is.null(fmt)) {
    dcc_abort("Cannot infer format from extension '.", ext,
              "'; pass `format` explicitly.", class = "dcc_format_error")
  }
  fmt
}

read_delim_dcc <- function(path, sep, encoding, ...) {
  if (encoding %in% c("UTF-8", "latin1")) {
    fread_enc <- if (encoding == "latin1") "Latin-1" else "UTF-8"
    dt <- data.table::fread(path, sep = sep, encoding = fread_enc,
                            na.strings = c("", "NA"), ...)
  } else {
    # fread only supports UTF-8/Latin-1 natively; convert via stringi.
    txt <- read_file_utf8(path, encoding)
    dt <- data.table::fread(text = txt, sep = sep,
                            na.strings = c("", "NA"), ...)
  }
  dt
}

read_excel_dcc <- function(path, ...) {
  dcc_require("readxl", "read Excel files")
  data.table::as.data.table(readxl::read_excel(path, ...))
}

read_haven_dcc <- function(path, kind, ...) {
  dcc_require("haven", "read SPSS/Stata/SAS files")
  x <- switch(kind,
    sav = haven::read_sav(path, ...),
    dta = haven::read_dta(path, ...),
    sas7bdat = haven::read_sas(path, ...)
  )
  # Keep haven_labelled columns intact: labels and user-defined missings
  # are survey metadata that detection rules consume later.
  data.table::as.data.table(x)
}

read_arrow_dcc <- function(path, kind, ...) {
  dcc_require("arrow", "read Parquet/Feather files")
  x <- switch(kind,
    parquet = arrow::read_parquet(path, ...),
    feather = arrow::read_feather(path, ...)
  )
  data.table::as.data.table(x)
}

read_json_dcc <- function(path, encoding, ...) {
  dcc_require("jsonlite", "read JSON files")
  txt <- read_file_utf8(path, encoding)
  x <- jsonlite::fromJSON(txt, ...)
  if (!is.data.frame(x)) {
    dcc_abort("JSON input must be rectangular (an array of records); ",
              "got ", paste(class(x), collapse = "/"), ".",
              class = "dcc_format_error")
  }
  data.table::as.data.table(x)
}
