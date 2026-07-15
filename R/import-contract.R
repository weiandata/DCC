missing_state_levels <- function() {
  c(
    "not_administered",
    "respondent_omission",
    "import_missing",
    "declared_missing_code",
    "cleared_by_cleaning"
  )
}

empty_dictionary <- function() {
  data.table::data.table(
    name = character(),
    source_name = character(),
    type = character(),
    role = character()
  )
}

empty_missing_states <- function() {
  data.table::data.table(
    row = integer(),
    variable = character(),
    state = character(),
    source_value = character()
  )
}

normalize_dictionary <- function(dictionary) {
  if (is.null(dictionary)) return(empty_dictionary())
  if (!is.data.frame(dictionary)) {
    dcc_abort("`dictionary` must be a data.frame.",
              class = "dcc_import_error")
  }
  dictionary <- data.table::copy(data.table::as.data.table(dictionary))
  required <- c("name", "source_name", "type", "role")
  missing <- setdiff(required, names(dictionary))
  if (length(missing)) {
    dcc_abort("`dictionary` is missing column(s): ",
              paste(missing, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  dictionary[, name := as.character(name)]
  if (anyNA(dictionary$name) || any(!nzchar(dictionary$name)) ||
      anyDuplicated(dictionary$name)) {
    dcc_abort("`dictionary$name` must contain unique non-empty names.",
              class = "dcc_import_error")
  }
  dictionary
}

normalize_missing_states <- function(missing_states) {
  if (is.null(missing_states)) return(empty_missing_states())
  if (!is.data.frame(missing_states)) {
    dcc_abort("`missing_states` must be a data.frame.",
              class = "dcc_import_error")
  }
  missing_states <- data.table::copy(
    data.table::as.data.table(missing_states)
  )
  required <- c("row", "variable", "state", "source_value")
  missing <- setdiff(required, names(missing_states))
  if (length(missing)) {
    dcc_abort("`missing_states` is missing column(s): ",
              paste(missing, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  missing_states[, state := as.character(state)]
  invalid <- setdiff(unique(missing_states$state), missing_state_levels())
  if (length(invalid)) {
    dcc_abort("Unknown missing state(s): ", paste(invalid, collapse = ", "),
              ".", class = "dcc_import_error")
  }
  if (anyNA(missing_states$row) || any(missing_states$row < 1) ||
      anyNA(missing_states$variable) ||
      any(!nzchar(as.character(missing_states$variable)))) {
    dcc_abort("Missing-state rows need a positive `row` and non-empty ",
              "`variable`.", class = "dcc_import_error")
  }
  missing_states
}

normalize_spec_table <- function(x, field) {
  if (!is.data.frame(x)) {
    dcc_abort("Import-spec `", field, "` must be a data.frame.",
              class = "dcc_import_error")
  }
  data.table::copy(data.table::as.data.table(x))
}

new_import_spec <- function(source, format, options = list(), columns,
                            values = data.frame(), missing = data.frame(),
                            multiselect = data.frame()) {
  if (!is.character(source) || length(source) != 1L || !file.exists(source)) {
    dcc_abort("Import-spec `source` must be one existing path.",
              class = "dcc_import_error")
  }
  if (!is.list(options)) {
    dcc_abort("Import-spec `options` must be a list.",
              class = "dcc_import_error")
  }
  adapter <- dcc_get_adapter(format)
  columns <- normalize_spec_table(columns, "columns")
  required <- c("source_name", "name")
  absent <- setdiff(required, names(columns))
  if (length(absent)) {
    dcc_abort("Import-spec `columns` is missing column(s): ",
              paste(absent, collapse = ", "), ".",
              class = "dcc_import_error")
  }
  for (column in required) {
    value <- as.character(columns[[column]])
    if (anyNA(value) || any(!nzchar(value)) || anyDuplicated(value)) {
      dcc_abort("Import-spec `columns$", column,
                "` must contain unique non-empty names.",
                class = "dcc_import_error")
    }
    data.table::set(columns, j = column, value = value)
  }
  structure(
    list(
      source = normalizePath(source, mustWork = TRUE),
      format = adapter$name,
      options = options,
      columns = columns,
      values = normalize_spec_table(values, "values"),
      missing = normalize_spec_table(missing, "missing"),
      multiselect = normalize_spec_table(multiselect, "multiselect")
    ),
    class = "dcc_import_spec"
  )
}
