adapter_haven <- function(name, extensions) {
  reader <- function(path, options = list()) {
    resolved <- resolve_compressed_source(path, options)
    on.exit(cleanup_resolved_source(resolved), add = TRUE)
    extension <- tolower(tools::file_ext(resolved))
    encoding <- options$encoding %||% NULL
    data <- tryCatch(
      read_haven_source(name, extension, resolved, options, encoding),
      error = function(e) {
        dcc_abort("Could not read ", toupper(name), " source: ",
                  conditionMessage(e), class = "dcc_import_error")
      }
    )
    validate_statistical_names(data, name)
    metadata <- capture_haven_metadata(data)
    raw <- lapply(data, statistical_scalar_character)
    raw <- as.data.frame(raw, check.names = FALSE, stringsAsFactors = FALSE)
    list(data = raw, metadata = metadata)
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
        fix = "Choose an existing statistical data file."
      )
    }
    allowed <- c("encoding", "catalog_file", "catalog_encoding", "member",
                 "compression", "max_uncompressed_bytes")
    unknown <- setdiff(names(spec$options), allowed)
    if (length(unknown)) {
      issues[[length(issues) + 1L]] <- val_issue(
        "IMPORT_UNKNOWN_OPTION", "fail", unknown[1L],
        fix = paste0("Remove unsupported statistical option(s): ",
                     paste(unknown, collapse = ", "), ".")
      )
    }
    new_validation(issues)
  }
  new_format_adapter(
    name, extensions, reader, inspector, validator, "Experimental",
    list(labels = "preserved", tagged_missing = "preserved",
         user_missing = "preserved", values = "source scalar codes",
         cleaning = FALSE, declared_structure = TRUE)
  )
}

read_haven_source <- function(name, extension, path, options, encoding) {
  add_encoding <- function(args) {
    if (!is.null(encoding)) args$encoding <- encoding
    args
  }
  switch(
    name,
    spss = if (extension == "por") {
      do.call(haven::read_por, add_encoding(list(
        file = path, .name_repair = "minimal"
      )))
    } else {
      do.call(haven::read_sav, add_encoding(list(
        file = path, user_na = TRUE, .name_repair = "minimal"
      )))
    },
    stata = do.call(haven::read_dta, add_encoding(list(
      file = path, .name_repair = "minimal"
    ))),
    sas = {
      args <- add_encoding(list(data_file = path, .name_repair = "minimal"))
      if (!is.null(options$catalog_file)) {
        args$catalog_file <- options$catalog_file
      }
      if (!is.null(options$catalog_encoding)) {
        args$catalog_encoding <- options$catalog_encoding
      }
      do.call(haven::read_sas, args)
    },
    xpt = haven::read_xpt(path, .name_repair = "minimal")
  )
}

validate_statistical_names <- function(data, format) {
  column_names <- names(data)
  if (anyNA(column_names) || any(!nzchar(column_names)) ||
      anyDuplicated(column_names)) {
    dcc_abort(toupper(format),
              " source columns must have unique non-empty names.",
              class = "dcc_import_error")
  }
  invisible(TRUE)
}

statistical_scalar_character <- function(column) {
  if (is.list(column)) {
    dcc_abort("Statistical sources cannot contain list columns.",
              class = "dcc_import_error")
  }
  if (inherits(column, "POSIXt")) {
    return(format(column, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  if (inherits(column, "Date")) return(format(column, "%Y-%m-%d"))
  as.character(column)
}

capture_haven_metadata <- function(data) {
  variables <- lapply(data, function(column) {
    list(
      label = attr(column, "label", exact = TRUE) %||% NA_character_,
      labels = attr(column, "labels", exact = TRUE) %||%
        stats::setNames(numeric(), character()),
      na_values = attr(column, "na_values", exact = TRUE),
      na_range = attr(column, "na_range", exact = TRUE),
      class = class(column)
    )
  })
  missing <- list()
  add_missing <- function(rows, variable, source_values) {
    if (!length(rows)) return(invisible(NULL))
    missing[[length(missing) + 1L]] <<- data.table::data.table(
      row = rows,
      variable = variable,
      state = "declared_missing_code",
      source_value = as.character(source_values)
    )
    invisible(NULL)
  }
  for (name in names(data)) {
    column <- data[[name]]
    raw <- as.character(column)
    na_values <- attr(column, "na_values", exact = TRUE)
    if (length(na_values)) {
      for (value in na_values) {
        rows <- which(!is.na(raw) & raw == as.character(value))
        add_missing(rows, name, rep(as.character(value), length(rows)))
      }
    }
    na_range <- attr(column, "na_range", exact = TRUE)
    if (length(na_range) == 2L && is.numeric(column)) {
      rows <- which(!is.na(column) & column >= na_range[1L] &
                      column <= na_range[2L])
      add_missing(rows, name, raw[rows])
    }
    tagged <- haven::is_tagged_na(column)
    if (any(tagged)) {
      rows <- which(tagged)
      tags <- haven::na_tag(column[rows])
      add_missing(rows, name, paste0("NA(", tags, ")"))
    }
  }
  missing <- if (length(missing)) {
    unique(data.table::rbindlist(missing, use.names = TRUE))
  } else {
    empty_missing_states()
  }
  list(backend = "haven", variables = variables, missing = missing)
}
