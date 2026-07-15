read_plan_sheet <- function(path, sheet, expected) {
  header <- openxlsx2::wb_to_df(
    path, sheet = sheet, rows = 1, col_names = FALSE,
    skip_empty_rows = FALSE, skip_empty_cols = FALSE, check_names = FALSE
  )
  actual <- as.character(header[1L, , drop = TRUE])
  if (!identical(actual, expected)) {
    dcc_abort("Sheet `", sheet, "` headers do not match strict template 1.0. ",
              "Expected: ", paste(expected, collapse = ", "), "; found: ",
              paste(actual, collapse = ", "), ".",
              class = "dcc_plan_error")
  }
  data <- openxlsx2::wb_to_df(
    path, sheet = sheet, start_row = 3, col_names = FALSE,
    skip_empty_rows = FALSE, skip_empty_cols = FALSE, check_names = FALSE
  )
  if (!nrow(data)) {
    return(as.data.frame(stats::setNames(
      rep(list(character()), length(expected)), expected
    ), stringsAsFactors = FALSE))
  }
  if (ncol(data) != length(expected)) {
    dcc_abort("Sheet `", sheet, "` data width does not match template 1.0.",
              class = "dcc_plan_error")
  }
  names(data) <- expected
  empty <- apply(data, 1L, function(row) {
    all(is.na(row) | !nzchar(trimws(as.character(row))))
  })
  data[!empty, , drop = FALSE]
}

read_plan_key_values <- function(table, section, expected) {
  keys <- as.character(table$key)
  if (!identical(keys, expected)) {
    dcc_abort("Sheet `", section, "` keys do not match strict template 1.0.",
              class = "dcc_plan_error")
  }
  values <- as.character(table$value)
  values[is.na(values)] <- ""
  stats::setNames(as.list(values), keys)
}

coerce_excel_plan_tables <- function(sections) {
  if (nrow(sections$columns)) {
    values <- tolower(as.character(sections$columns$required))
    if (all(is.na(values) | values %in% c("true", "false"))) {
      sections$columns$required <- ifelse(
        is.na(values), NA, values == "true"
      )
    }
  }
  sections
}

plan_excel_locations <- function(sections, path) {
  rows <- list()
  add <- function(field, index, sheet, row, column) {
    rows[[length(rows) + 1L]] <<- data.table::data.table(
      field = field, index = as.integer(index), sheet = sheet,
      row = as.integer(row), column = column, cell = paste0(column, row)
    )
  }
  for (section in c("project", "source")) {
    tab <- sections[[section]]
    for (i in seq_len(nrow(tab))) {
      add(paste0(section, ".", tab$key[i]), NA_integer_, section, i + 2L, "B")
    }
  }
  for (section in names(plan_table_contracts())) {
    tab <- sections[[section]]
    for (j in seq_along(tab)) {
      column <- openxlsx2::int2col(j)
      for (i in seq_len(nrow(tab))) {
        add(paste0(section, ".", names(tab)[j]), i, section, i + 2L, column)
      }
    }
  }
  if (!length(rows)) {
    return(data.table::data.table(
      field = character(), index = integer(), sheet = character(),
      row = integer(), column = character(), cell = character()
    ))
  }
  data.table::rbindlist(rows)
}

read_plan_excel <- function(path) {
  wb <- tryCatch(openxlsx2::wb_load(path, data_only = TRUE),
                 error = function(e) {
                   dcc_abort("Could not open strict plan workbook: ",
                             conditionMessage(e), class = "dcc_plan_error")
                 })
  expected_sheets <- names(plan_sheet_contracts())
  actual_sheets <- unname(openxlsx2::wb_get_sheet_names(wb))
  if (!identical(actual_sheets, expected_sheets)) {
    dcc_abort("Workbook sheets do not match strict template 1.0. Expected: ",
              paste(expected_sheets, collapse = ", "), "; found: ",
              paste(actual_sheets, collapse = ", "), ".",
              class = "dcc_plan_error")
  }
  sections <- lapply(expected_sheets, function(sheet) {
    read_plan_sheet(path, sheet, plan_sheet_contracts()[[sheet]])
  })
  names(sections) <- expected_sheets
  sections <- coerce_excel_plan_tables(sections)
  defaults <- plan_template_defaults("zh-CN")
  project <- read_plan_key_values(
    sections$project, "project", defaults$project$key
  )
  source <- read_plan_key_values(
    sections$source, "source", defaults$source$key
  )
  if (!identical(as.character(sections$outputs$key), defaults$outputs$key)) {
    dcc_abort("Sheet `outputs` keys do not match strict template 1.0.",
              class = "dcc_plan_error")
  }
  plan <- new_dcc_plan(
    project, source, sections$columns, sections$values, sections$missing,
    sections$multiselect, sections$rules, sections$actions, sections$outputs
  )
  attr(plan, "dcc_plan_source") <- list(
    type = "xlsx", path = normalizePath(path, mustWork = TRUE),
    locations = plan_excel_locations(sections, path)
  )
  plan
}

json_plan_table <- function(x, section) {
  if (is.null(x) || !length(x)) return(empty_plan_table(section))
  if (is.data.frame(x)) return(x)
  tryCatch(as.data.frame(x, stringsAsFactors = FALSE), error = function(e) {
    dcc_abort("JSON section `", section, "` must be an array of objects.",
              class = "dcc_plan_error")
  })
}

read_plan_json <- function(path) {
  raw <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE, simplifyDataFrame = TRUE),
    error = function(e) {
      dcc_abort("Could not parse JSON plan: ", conditionMessage(e),
                class = "dcc_plan_error")
    }
  )
  if (!is.list(raw) || !identical(names(raw), plan_section_names())) {
    dcc_abort("JSON plan sections do not match strict contract 1.0.",
              class = "dcc_plan_error")
  }
  plan <- new_dcc_plan(
    raw$project, raw$source, json_plan_table(raw$columns, "columns"),
    json_plan_table(raw$values, "values"),
    json_plan_table(raw$missing, "missing"),
    json_plan_table(raw$multiselect, "multiselect"),
    json_plan_table(raw$rules, "rules"),
    json_plan_table(raw$actions, "actions"),
    json_plan_table(raw$outputs, "outputs")
  )
  attr(plan, "dcc_plan_source") <- list(
    type = "json", path = normalizePath(path, mustWork = TRUE)
  )
  plan
}

#' Read a strict DCC Excel or JSON plan
#'
#' Reads only the exact version-1.0 contract. Unknown, missing, reordered, or
#' renamed workbook sheets and columns are rejected instead of guessed.
#'
#' @param path Existing `.xlsx` or `.json` plan path.
#' @return A `dcc_plan`. Excel plans retain cell-location metadata used by
#'   `dcc_validate_plan()`; JSON validation uses JSON Pointers.
#' @export
dcc_read_plan <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || !file.exists(path)) {
    dcc_abort("Plan path does not exist: ", path %||% "<missing>",
              class = "dcc_plan_error")
  }
  extension <- tolower(tools::file_ext(path))
  if (extension == "xlsx") return(read_plan_excel(path))
  if (extension == "json") return(read_plan_json(path))
  dcc_abort("Plan must be a strict .xlsx or .json file.",
            class = "dcc_plan_error")
}
