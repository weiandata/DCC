spreadsheet_structure <- function(options) {
  sheet <- options$sheet
  range <- options$range
  if ((!is.character(sheet) && !is.numeric(sheet)) || length(sheet) != 1L ||
      is.na(sheet)) {
    dcc_abort("Spreadsheet import requires one declared `sheet`.",
              class = "dcc_import_error")
  }
  if (!is.character(range) || length(range) != 1L || is.na(range) ||
      !nzchar(range)) {
    dcc_abort("Spreadsheet import requires one declared `range`.",
              class = "dcc_import_error")
  }
  list(sheet = sheet, range = range)
}

spreadsheet_validator <- function(path, spec) {
  issues <- list()
  if (!file.exists(path)) {
    issues[[length(issues) + 1L]] <- val_issue(
      "IMPORT_SOURCE_MISSING", "fail", "source",
      fix = "Choose an existing source workbook."
    )
  }
  sheet <- spec$options$sheet
  if (((!is.character(sheet) && !is.numeric(sheet)) ||
       length(sheet) != 1L || is.na(sheet))) {
    issues[[length(issues) + 1L]] <- val_issue(
      "IMPORT_SHEET_REQUIRED", "fail", "sheet",
      fix = "Declare one worksheet name or position."
    )
  }
  range <- spec$options$range
  if (!is.character(range) || length(range) != 1L || is.na(range) ||
      !nzchar(range)) {
    issues[[length(issues) + 1L]] <- val_issue(
      "IMPORT_RANGE_REQUIRED", "fail", "range",
      fix = "Declare one exact worksheet range."
    )
  }
  allowed <- c("sheet", "range", "member", "compression",
               "max_uncompressed_bytes")
  unknown <- setdiff(names(spec$options), allowed)
  if (length(unknown)) {
    issues[[length(issues) + 1L]] <- val_issue(
      "IMPORT_UNKNOWN_OPTION", "fail", unknown[1L],
      fix = paste0("Remove unsupported spreadsheet option(s): ",
                   paste(unknown, collapse = ", "), ".")
    )
  }
  new_validation(issues)
}

validate_spreadsheet_raw <- function(data, format) {
  if (!is.data.frame(data)) {
    dcc_abort(format, " adapter did not return a rectangular table.",
              class = "dcc_import_error")
  }
  column_names <- names(data)
  if (anyNA(column_names) || any(!nzchar(column_names)) ||
      anyDuplicated(column_names)) {
    dcc_abort(format, " source columns must have unique non-empty names.",
              class = "dcc_import_error")
  }
  out <- lapply(data, function(column) {
    if (is.list(column)) {
      dcc_abort(format, " source contains a non-scalar column.",
                class = "dcc_import_error")
    }
    as.character(column)
  })
  as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
}

adapter_readxl <- function(format) {
  reader <- function(path, options = list()) {
    structure <- spreadsheet_structure(options)
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    result <- tryCatch({
      text_data <- readxl::read_excel(
        resolved, sheet = structure$sheet, range = structure$range,
        col_types = "text", trim_ws = FALSE, .name_repair = "minimal"
      )
      typed_data <- suppressWarnings(readxl::read_excel(
        resolved, sheet = structure$sheet, range = structure$range,
        trim_ws = FALSE, .name_repair = "minimal"
      ))
      list(data = restore_readxl_temporal_values(text_data, typed_data),
           column_classes = lapply(typed_data, class))
    },
      error = function(e) {
        dcc_abort("Could not read ", toupper(format), " workbook: ",
                  conditionMessage(e), class = "dcc_import_error")
      }
    )
    list(
      data = validate_spreadsheet_raw(result$data, toupper(format)),
      metadata = list(backend = "readxl", sheet = structure$sheet,
                      range = structure$range,
                      formula_policy = "cached display values",
                      source_column_classes = result$column_classes)
    )
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  new_format_adapter(
    format, format, reader, inspector, spreadsheet_validator,
    "Experimental",
    list(values = "cell display values as character", sheet = "declared",
         range = "declared", formulas = "cached values", cleaning = FALSE,
         declared_structure = TRUE)
  )
}

restore_readxl_temporal_values <- function(text_data, typed_data) {
  if (!identical(dim(text_data), dim(typed_data)) ||
      !identical(names(text_data), names(typed_data))) {
    return(text_data)
  }
  for (name in names(typed_data)) {
    typed <- typed_data[[name]]
    if (inherits(typed, "POSIXt")) {
      clock <- format(typed, "%H:%M:%OS", tz = "UTC")
      date_only <- all(is.na(clock) | clock == "00:00:00")
      text_data[[name]] <- if (date_only) {
        format(typed, "%Y-%m-%d", tz = "UTC")
      } else {
        format(typed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      }
    } else if (inherits(typed, "Date")) {
      text_data[[name]] <- format(typed, "%Y-%m-%d")
    }
  }
  text_data
}

adapter_ods <- function() {
  reader <- function(path, options = list()) {
    structure <- spreadsheet_structure(options)
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    data <- tryCatch(
      readODS::read_ods(
        resolved, sheet = structure$sheet, range = structure$range,
        col_types = NA, guess = FALSE, as_tibble = FALSE,
        .name_repair = "minimal", trim_ws = FALSE
      ),
      error = function(e) {
        dcc_abort("Could not read ODS workbook: ", conditionMessage(e),
                  class = "dcc_import_error")
      }
    )
    list(
      data = validate_spreadsheet_raw(data, "ODS"),
      metadata = list(backend = "readODS", sheet = structure$sheet,
                      range = structure$range,
                      formula_policy = "stored values")
    )
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  new_format_adapter(
    "ods", "ods", reader, inspector, spreadsheet_validator,
    "Experimental",
    list(values = "cell values as character", sheet = "declared",
         range = "declared", formulas = "stored values", cleaning = FALSE,
         declared_structure = TRUE)
  )
}

adapter_xlsb <- function() {
  limitations <- c(
    "formula and array-formula coverage is incomplete",
    "data validations and conditional formatting are not preserved",
    "pivot tables and slicers are not supported",
    "the parser is intended only for valid workbooks",
    "the backend supports little-endian systems only"
  )
  reader <- function(path, options = list()) {
    structure <- spreadsheet_structure(options)
    if (.Platform$endian != "little") {
      dcc_abort("The limited XLSB backend requires a little-endian system.",
                class = "dcc_import_error")
    }
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    workbook <- tryCatch(
      openxlsx2::wb_load(resolved, sheet = structure$sheet, data_only = TRUE),
      error = function(e) {
        dcc_abort("The limited XLSB backend could not load this workbook: ",
                  conditionMessage(e), class = "dcc_import_error")
      }
    )
    data <- tryCatch(
      openxlsx2::wb_to_df(
        workbook, sheet = structure$sheet, dims = structure$range,
        row_names = FALSE, col_names = TRUE, detect_dates = FALSE,
        convert = FALSE, check_names = FALSE
      ),
      error = function(e) {
        dcc_abort("The limited XLSB backend could not read the declared ",
                  "range: ", conditionMessage(e),
                  class = "dcc_import_error")
      }
    )
    list(
      data = validate_spreadsheet_raw(data, "XLSB"),
      metadata = list(backend = "openxlsx2", sheet = structure$sheet,
                      range = structure$range, limitations = limitations,
                      data_only = TRUE)
    )
  }
  inspector <- function(path, options = list()) {
    raw <- reader(path, options)
    list(columns = names(raw$data), rows = nrow(raw$data),
         metadata = raw$metadata)
  }
  new_format_adapter(
    "xlsb", "xlsb", reader, inspector, spreadsheet_validator,
    "Experimental",
    list(values = "limited binary workbook parser", sheet = "declared",
         range = "declared", limitations = limitations, cleaning = FALSE,
         declared_structure = TRUE)
  )
}
