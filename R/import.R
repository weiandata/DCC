#' Strict canonical import
#'
#' Reads a source through its registered format adapter and applies an explicit
#' import specification. Source names, canonical names, types, missing codes,
#' and roles are declared rather than guessed. The source file is never
#' modified.
#'
#' @param path Path to the source file.
#' @param spec A `dcc_import_spec` created internally from a strict DCC plan.
#' @return A [dcc_data()] object with canonical data, dictionary, missing
#'   states, import specification, source metadata, and import provenance.
#' @export
dcc_import <- function(path, spec) {
  if (!inherits(spec, "dcc_import_spec")) {
    dcc_abort("`spec` must be a dcc_import_spec.", class = "dcc_type_error")
  }
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    dcc_abort("`path` must be one existing source file.",
              class = "dcc_import_error")
  }
  normalized <- normalizePath(path, mustWork = TRUE)
  if (!identical(normalized, spec$source)) {
    dcc_abort("Import path does not match the source bound to `spec`.",
              class = "dcc_import_error")
  }

  started <- dcc_timestamp()
  adapter <- dcc_get_adapter(spec$format)
  issues <- adapter$validator(normalized, spec)
  if (!inherits(issues, "dcc_validation")) {
    dcc_abort("Format adapter returned an invalid validation report.",
              class = "dcc_import_error")
  }
  errors <- dcc_validation_errors(issues)
  if (nrow(errors)) {
    dcc_abort("Import plan validation failed: ", errors$code[1L], " (",
              errors$fix[1L], ")",
              class = "dcc_import_error")
  }
  raw <- adapter$reader(normalized, spec$options)
  validate_adapter_result(raw, adapter$name)
  canonicalize_import(raw$data, raw$metadata, spec,
                      started_at = started)
}

validate_adapter_result <- function(raw, format) {
  if (!is.list(raw) || !is.data.frame(raw$data) ||
      !is.list(raw$metadata %||% list())) {
    dcc_abort("Format adapter '", format,
              "' returned an invalid raw-data contract.",
              class = "dcc_import_error")
  }
  invisible(TRUE)
}

canonicalize_import <- function(raw_data, raw_metadata, spec,
                                started_at = dcc_timestamp()) {
  raw <- data.table::copy(data.table::as.data.table(raw_data))
  raw_names <- names(raw)
  if (anyNA(raw_names) || any(!nzchar(raw_names)) || anyDuplicated(raw_names)) {
    dcc_abort("Source columns must have unique non-empty names.",
              class = "dcc_import_error")
  }
  declared <- as.character(spec$columns$source_name)
  extra <- setdiff(raw_names, declared)
  absent <- setdiff(declared, raw_names)
  if (length(extra)) {
    dcc_abort("Undeclared source column(s): ", paste(extra, collapse = ", "),
              ".", class = "dcc_import_error")
  }
  if (length(absent)) {
    dcc_abort("Declared source column(s) not found: ",
              paste(absent, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  if (!"type" %in% names(spec$columns)) {
    dcc_abort("Import-spec `columns` must declare `type`.",
              class = "dcc_import_error")
  }

  columns <- data.table::copy(spec$columns)
  if (!"role" %in% names(columns)) columns[, role := "other"]
  columns[, type := tolower(as.character(type))]
  columns[, role := as.character(role)]
  allowed_types <- c("character", "integer", "double", "numeric",
                     "logical", "date", "datetime")
  invalid_types <- setdiff(unique(columns$type), allowed_types)
  if (length(invalid_types)) {
    dcc_abort("Unsupported canonical type(s): ",
              paste(invalid_types, collapse = ", "), ".",
              class = "dcc_import_error")
  }

  missing_plan <- validate_missing_plan(spec$missing, columns$name)
  canonical <- data.table::data.table()
  missing_rows <- vector("list", nrow(columns))

  for (j in seq_len(nrow(columns))) {
    source_name <- columns$source_name[j]
    canonical_name <- columns$name[j]
    values <- as.character(raw[[source_name]])
    states <- rep.int(NA_character_, length(values))
    source_values <- rep.int(NA_character_, length(values))
    imported_missing <- is.na(values) | values == ""
    states[imported_missing] <- "import_missing"
    source_values[imported_missing] <- values[imported_missing]

    source_missing <- source_missing_for_column(
      raw_metadata$missing, source_name, length(values)
    )
    if (nrow(source_missing)) {
      states[source_missing$row] <- source_missing$state
      source_values[source_missing$row] <- source_missing$source_value
    }

    declared_missing <- missing_plan[missing_plan$variable == canonical_name, ]
    if (nrow(declared_missing)) {
      for (k in seq_len(nrow(declared_missing))) {
        hit <- !is.na(values) & values == declared_missing$source_value[k]
        states[hit] <- declared_missing$state[k]
        source_values[hit] <- values[hit]
      }
    }
    values[!is.na(states)] <- NA_character_
    converted <- convert_import_column(
      values, columns$type[j], source_name, source_rows = seq_along(values) + 1L
    )
    data.table::set(canonical, j = canonical_name, value = converted)

    hit <- which(!is.na(states))
    if (length(hit)) {
      missing_rows[[j]] <- data.table::data.table(
        row = hit,
        variable = canonical_name,
        state = states[hit],
        source_value = source_values[hit]
      )
    }
  }

  missing_states <- if (length(Filter(Negate(is.null), missing_rows))) {
    data.table::rbindlist(missing_rows, use.names = TRUE)
  } else {
    empty_missing_states()
  }
  data.table::setorderv(missing_states, c("row", "variable"))

  dictionary <- enrich_import_dictionary(columns, raw_metadata$variables)
  dictionary[, type := fifelse(type == "numeric", "double", type)]
  file_hash <- unname(tools::md5sum(spec$source))
  spec_hash <- hash_import_spec(spec)
  meta <- list(
    source = spec$source,
    format = spec$format,
    encoding = raw_metadata$encoding %||% "native",
    file_hash = file_hash,
    import_spec_hash = spec_hash,
    file_size = file.size(spec$source),
    read_time = dcc_timestamp(),
    dcc_version = dcc_version_string(),
    adapter_metadata = raw_metadata
  )
  report <- dcc_l0_diagnose(canonical, meta)
  dcc_data(
    canonical,
    meta = meta,
    read_report = report,
    dictionary = dictionary,
    missing_states = missing_states,
    import_spec = spec,
    provenance = list(new_provenance_record(
      stage = "import",
      started_at = started_at,
      ended_at = dcc_timestamp(),
      hashes = list(input = file_hash, import_spec = spec_hash),
      counts = list(rows = nrow(canonical), columns = ncol(canonical),
                    missing_states = nrow(missing_states),
                    l0_findings = nrow(report$findings)),
      details = list(format = spec$format, source = spec$source,
                     adapter_status = dcc_get_adapter(spec$format)$status)
    ))
  )
}

source_missing_for_column <- function(source_missing, source_name, n_rows) {
  if (is.null(source_missing) || !nrow(source_missing)) {
    return(data.table::data.table(row = integer(), state = character(),
                                  source_value = character()))
  }
  required <- c("row", "variable", "state", "source_value")
  if (!is.data.frame(source_missing) ||
      length(setdiff(required, names(source_missing)))) {
    dcc_abort("Adapter missing metadata has an invalid contract.",
              class = "dcc_import_error")
  }
  out <- data.table::as.data.table(source_missing)
  out <- out[as.character(variable) == source_name, required, with = FALSE]
  if (nrow(out) && (anyNA(out$row) || any(out$row < 1L | out$row > n_rows) ||
                    any(!out$state %in% missing_state_levels()))) {
    dcc_abort("Adapter missing metadata contains invalid rows or states.",
              class = "dcc_import_error")
  }
  out
}

enrich_import_dictionary <- function(columns, variables) {
  dictionary <- data.table::copy(columns)
  variables <- variables %||% list()
  source_metadata <- function(source_name, field, default) {
    item <- variables[[source_name]]
    if (is.null(item) || is.null(item[[field]])) default else item[[field]]
  }
  source_labels <- vapply(
    dictionary$source_name,
    source_metadata,
    field = "label",
    default = NA_character_,
    FUN.VALUE = character(1)
  )
  if (!"label" %in% names(dictionary)) {
    dictionary[, label := source_labels]
  } else {
    fill <- is.na(dictionary$label) | !nzchar(as.character(dictionary$label))
    dictionary[fill, label := source_labels[fill]]
  }
  if (!"value_labels" %in% names(dictionary)) {
    dictionary[, value_labels := lapply(source_name, function(name) {
      source_metadata(name, "labels", stats::setNames(numeric(), character()))
    })]
  }
  if (!"source_class" %in% names(dictionary)) {
    dictionary[, source_class := vapply(
      source_name,
      function(name) paste(source_metadata(name, "class", character()),
                            collapse = "/"),
      character(1)
    )]
  }
  dictionary
}

validate_missing_plan <- function(missing, variables) {
  if (!nrow(missing)) {
    return(data.table::data.table(variable = character(),
                                  source_value = character(),
                                  state = character()))
  }
  required <- c("variable", "source_value", "state")
  absent <- setdiff(required, names(missing))
  if (length(absent)) {
    dcc_abort("Import-spec `missing` is missing column(s): ",
              paste(absent, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  missing <- data.table::copy(missing)
  missing[, variable := as.character(variable)]
  missing[, source_value := as.character(source_value)]
  missing[, state := as.character(state)]
  unknown_variables <- setdiff(unique(missing$variable), variables)
  if (length(unknown_variables)) {
    dcc_abort("Missing-code plan references unknown variable(s): ",
              paste(unknown_variables, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  unknown_states <- setdiff(unique(missing$state), missing_state_levels())
  if (length(unknown_states)) {
    dcc_abort("Missing-code plan uses unknown state(s): ",
              paste(unknown_states, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  key <- paste(missing$variable, missing$source_value, sep = "\r")
  if (anyDuplicated(key)) {
    dcc_abort("Missing-code mappings must be unique per variable and value.",
              class = "dcc_import_error")
  }
  missing
}

convert_import_column <- function(x, type, source_name, source_rows) {
  type <- if (type == "numeric") "double" else type
  nonmissing <- !is.na(x)
  out <- switch(
    type,
    character = x,
    integer = suppressWarnings(as.integer(x)),
    double = suppressWarnings(as.numeric(x)),
    logical = {
      normalized <- tolower(x)
      value <- rep.int(NA, length(x))
      value[normalized %in% c("true", "1")] <- TRUE
      value[normalized %in% c("false", "0")] <- FALSE
      value
    },
    date = suppressWarnings(as.Date(x, format = "%Y-%m-%d")),
    datetime = parse_import_datetime(x)
  )
  invalid <- nonmissing & (is.na(out) |
    (type == "double" & !is.finite(out)))
  if (any(invalid)) {
    i <- which(invalid)[1L]
    dcc_abort("Cannot convert value '", x[i], "' at source row ",
              source_rows[i], ", column '", source_name, "' to ", type, ".",
              class = "dcc_import_error")
  }
  out
}

parse_import_datetime <- function(x) {
  out <- as.POSIXct(rep.int(NA_real_, length(x)), origin = "1970-01-01",
                    tz = "UTC")
  formats <- c("%Y-%m-%dT%H:%M:%OSZ", "%Y-%m-%dT%H:%M:%OS",
               "%Y-%m-%d %H:%M:%OS")
  remaining <- which(!is.na(x))
  for (format in formats) {
    if (!length(remaining)) break
    parsed <- as.POSIXct(strptime(x[remaining], format = format, tz = "UTC"))
    good <- !is.na(parsed)
    out[remaining[good]] <- parsed[good]
    remaining <- remaining[!good]
  }
  out
}

hash_import_spec <- function(spec) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(unclass(spec), tmp, version = 2, compress = FALSE)
  unname(tools::md5sum(tmp))
}
