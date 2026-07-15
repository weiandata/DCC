plan_sheet_contracts <- function() {
  c(list(project = c("key", "value"), source = c("key", "value")),
    plan_table_contracts())
}

plan_sheet_instructions <- function(language = "zh-CN") {
  zh <- list(
    project = c("\u56fa\u5b9a\u9879\u76ee\u5b57\u6bb5\uff08\u4e0d\u8981\u4fee\u6539\u5217\u540d\uff09",
                "\u5728\u9ec4\u8272\u5355\u5143\u683c\u586b\u5199"),
    source = c("\u56fa\u5b9a\u6570\u636e\u6e90\u5b57\u6bb5\uff08\u4e0d\u8981\u4fee\u6539\u5217\u540d\uff09",
               "\u5728\u9ec4\u8272\u5355\u5143\u683c\u586b\u5199\uff1b\u4e0d\u9002\u7528\u53ef\u7559\u7a7a"),
    columns = c("\u539f\u59cb\u5217\u540d", "\u6807\u51c6\u5217\u540d",
                "\u6570\u636e\u7c7b\u578b", "\u7528\u9014",
                "\u662f\u5426\u5fc5\u9700 TRUE/FALSE",
                "\u4e2d\u82f1\u6587\u6807\u7b7e"),
    values = c("\u6807\u51c6\u5217\u540d", "\u539f\u59cb\u53d6\u503c",
               "\u53d6\u503c\u6807\u7b7e"),
    missing = c("\u6807\u51c6\u5217\u540d", "\u539f\u59cb\u7f3a\u5931\u7801",
                "\u7f3a\u5931\u72b6\u6001"),
    multiselect = c("\u9898\u76ee\u540d", "\u5e03\u5c40",
                    "\u539f\u59cb\u5217\u6216\u5b57\u6bb5",
                    "\u9009\u9879\u503c", "\u5206\u9694\u7b26"),
    rules = c("\u89c4\u5219\u7f16\u53f7", "\u89c4\u5219\u7c7b\u578b",
              "\u6807\u51c6\u5217\u540d", "JSON \u53c2\u6570",
              "\u4e25\u91cd\u7a0b\u5ea6"),
    actions = c("\u89c4\u5219\u7f16\u53f7", "\u5904\u7406\u52a8\u4f5c",
                "JSON \u53c2\u6570\uff1b\u65e0\u53c2\u6570\u586b {}"),
    outputs = c("\u56fa\u5b9a\u8f93\u51fa\u8bbe\u7f6e",
                "\u8bbe\u7f6e\u503c")
  )
  en <- list(
    project = c("Fixed project field (do not rename)", "Enter values in yellow cells"),
    source = c("Fixed source field (do not rename)", "Enter yellow cells; leave optional values blank"),
    columns = c("Source column", "Canonical name", "Data type", "Role", "Required TRUE/FALSE", "Bilingual label"),
    values = c("Canonical name", "Source value", "Value label"),
    missing = c("Canonical name", "Source missing code", "Missing state"),
    multiselect = c("Item", "Layout", "Source column/field", "Option value", "Delimiter"),
    rules = c("Rule id", "Rule type", "Canonical name", "JSON parameters", "Severity"),
    actions = c("Rule id", "Action", "JSON parameters; use {} if none"),
    outputs = c("Fixed output setting", "Setting value")
  )
  primary <- if (identical(language, "zh-CN")) zh else en
  secondary <- if (identical(language, "zh-CN")) en else zh
  Map(function(a, b) paste(a, b, sep = " / "), primary, secondary)
}

plan_template_defaults <- function(language) {
  list(
    project = data.frame(
      key = c("template_version", "project_id", "project_name", "language",
              "created_by", "notes"),
      value = c("1.0", "", "", language, "", ""),
      stringsAsFactors = FALSE
    ),
    source = data.frame(
      key = plan_source_fields(), value = "", stringsAsFactors = FALSE
    ),
    outputs = data.frame(
      key = plan_output_key_profiles()$current,
      value = c(language, "csv", "TRUE", "TRUE", "TRUE", "parquet",
                "FALSE"),
      stringsAsFactors = FALSE
    )
  )
}

inline_validation <- function(values) {
  paste0('"', paste(values, collapse = ","), '"')
}

add_template_validation <- function(wb, sheet, dims, values, language) {
  title <- if (language == "zh-CN") {
    "\u8bf7\u9009\u62e9\u6709\u6548\u503c / Choose a value"
  } else {
    "Choose a valid value / \u8bf7\u9009\u62e9\u6709\u6548\u503c"
  }
  message <- paste(values, collapse = ", ")
  openxlsx2::wb_add_data_validation(
    wb, sheet = sheet, dims = dims, type = "list",
    value = inline_validation(values), allow_blank = TRUE,
    show_error_msg = TRUE, error_style = "stop", error_title = title,
    error = message, prompt_title = title, prompt = message
  )
}

style_template_sheet <- function(wb, sheet, ncol, input_dims, used_rows) {
  last_col <- openxlsx2::int2col(ncol)
  header <- paste0("A1:", last_col, "1")
  instructions <- paste0("A2:", last_col, "2")
  used <- paste0("A1:", last_col, used_rows)
  wb <- openxlsx2::wb_add_fill(
    wb, sheet, header, color = openxlsx2::wb_color(hex = "FF1F4E78")
  )
  wb <- openxlsx2::wb_add_font(
    wb, sheet, header, color = openxlsx2::wb_color(hex = "FFFFFFFF"),
    bold = TRUE, size = 11
  )
  wb <- openxlsx2::wb_add_fill(
    wb, sheet, instructions, color = openxlsx2::wb_color(hex = "FFD9EAF7")
  )
  wb <- openxlsx2::wb_add_font(
    wb, sheet, instructions, color = openxlsx2::wb_color(hex = "FF365F7D"),
    italic = TRUE, size = 10
  )
  wb <- openxlsx2::wb_add_fill(
    wb, sheet, input_dims, color = openxlsx2::wb_color(hex = "FFFFF2CC")
  )
  wb <- openxlsx2::wb_add_cell_style(
    wb, sheet, used, vertical = "center", wrap_text = TRUE
  )
  wb <- openxlsx2::wb_add_cell_style(
    wb, sheet, input_dims, locked = FALSE, apply_protection = TRUE
  )
  wb <- openxlsx2::wb_add_border(
    wb, sheet, header, bottom_border = "medium", left_border = "",
    right_border = "", top_border = "", bottom_color =
      openxlsx2::wb_color(hex = "FF1F4E78")
  )
  wb <- openxlsx2::wb_set_row_heights(wb, sheet, rows = 1, heights = 24)
  wb <- openxlsx2::wb_set_row_heights(wb, sheet, rows = 2, heights = 54)
  wb <- openxlsx2::wb_freeze_pane(wb, sheet, first_active_row = 3)
  wb <- openxlsx2::wb_set_sheetview(wb, sheet, show_grid_lines = FALSE,
                                    zoom_scale = 90)
  openxlsx2::wb_protect_worksheet(wb, sheet, protect = TRUE, password = NULL)
}

build_plan_workbook <- function(language = "zh-CN") {
  contracts <- plan_sheet_contracts()
  instructions <- plan_sheet_instructions(language)
  defaults <- plan_template_defaults(language)
  wb <- openxlsx2::wb_workbook(
    creator = "DCC", title = "DCC strict cleaning plan 1.0",
    subject = "Protected bilingual survey cleaning plan",
    company = "WEIAN DATA TECH (Beijing) Co., Ltd.",
    datetime_created = as.POSIXct("2026-07-15 00:00:00", tz = "UTC")
  )
  wb <- openxlsx2::wb_set_base_font(wb, font_size = 10, font_name = "Aptos")

  for (sheet in names(contracts)) {
    wb <- openxlsx2::wb_add_worksheet(wb, sheet = sheet, grid_lines = FALSE,
                                     zoom = 90)
    wb <- openxlsx2::wb_add_data(wb, sheet, as.list(contracts[[sheet]]),
                                start_row = 1, col_names = FALSE)
    wb <- openxlsx2::wb_add_data(wb, sheet, as.list(instructions[[sheet]]),
                                start_row = 2, col_names = FALSE)

    if (sheet %in% names(defaults)) {
      values <- defaults[[sheet]]
      wb <- openxlsx2::wb_add_data(wb, sheet, values, start_row = 3,
                                  col_names = FALSE, na = "")
      input_dims <- if (sheet == "project") {
        paste0("B4:B", nrow(values) + 2L)
      } else {
        paste0("B3:B", nrow(values) + 2L)
      }
      used_rows <- nrow(values) + 2L
    } else {
      input_dims <- paste0("A3:", openxlsx2::int2col(length(contracts[[sheet]])),
                           "102")
      used_rows <- 102L
    }
    wb <- style_template_sheet(wb, sheet, length(contracts[[sheet]]),
                               input_dims, used_rows)
    wb <- openxlsx2::wb_set_col_widths(
      wb, sheet, cols = 1,
      widths = if (sheet %in% c("project", "source", "outputs")) 26 else 20
    )
    if (length(contracts[[sheet]]) > 1L) {
      wb <- openxlsx2::wb_set_col_widths(
        wb, sheet, cols = 2:length(contracts[[sheet]]),
        widths = if (sheet %in% c("project", "source", "outputs")) 34 else 24
      )
    }
  }

  wb <- add_template_validation(wb, "project", "B6", c("zh-CN", "en"),
                                language)
  wb <- add_template_validation(wb, "source", "B4",
                                names(dcc_format_registry()), language)
  wb <- add_template_validation(wb, "columns", "C3:C102",
                                plan_column_types(), language)
  wb <- add_template_validation(wb, "columns", "D3:D102",
                                plan_column_roles(), language)
  wb <- add_template_validation(wb, "columns", "E3:E102",
                                c("TRUE", "FALSE"), language)
  wb <- add_template_validation(wb, "missing", "C3:C102",
                                missing_state_levels(), language)
  wb <- add_template_validation(wb, "multiselect", "B3:B102",
                                c("delimited", "columns"), language)
  wb <- add_template_validation(wb, "rules", "B3:B102", dcc_rule_types(),
                                language)
  wb <- add_template_validation(wb, "rules", "E3:E102",
                                c("info", "warn", "fail"), language)
  wb <- add_template_validation(wb, "actions", "B3:B102",
                                dcc_action_types(), language)
  wb <- add_template_validation(wb, "outputs", "B3", c("zh-CN", "en"),
                                language)
  wb <- add_template_validation(wb, "outputs", "B4",
                                c("csv", "xlsx", "parquet"), language)
  wb <- add_template_validation(wb, "outputs", "B5:B7",
                                c("TRUE", "FALSE"), language)
  wb <- add_template_validation(wb, "outputs", "B8",
                                c("parquet", "csv"), language)
  wb <- add_template_validation(wb, "outputs", "B9",
                                c("TRUE", "FALSE"), language)
  wb <- openxlsx2::wb_protect(wb, protect = TRUE, password = NULL,
                              lock_structure = TRUE)
  wb
}

#' Create the strict bilingual DCC Excel template
#'
#' Writes a protected version-1.0 workbook for survey staff. Machine headers
#' and workbook structure are locked; yellow input cells remain editable. Sheet
#' protection has no password and prevents accidental edits only.
#'
#' @param path Destination `.xlsx` path. Existing files are never overwritten.
#' @param language Primary instruction language, `"zh-CN"` or `"en"`; both
#'   languages remain visible in the workbook.
#' @return The normalized destination path, invisibly.
#' @export
dcc_template <- function(path = "DCC-cleaning-plan.xlsx", language = "zh-CN") {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || tolower(tools::file_ext(path)) != "xlsx") {
    dcc_abort("`path` must be one .xlsx file path.",
              class = "dcc_template_error")
  }
  if (!language %in% c("zh-CN", "en")) {
    dcc_abort("`language` must be `zh-CN` or `en`.",
              class = "dcc_template_error")
  }
  if (file.exists(path)) {
    dcc_abort("Template destination already exists: ", path,
              class = "dcc_template_error")
  }
  parent <- dirname(path)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    dcc_abort("Could not create template directory: ", parent,
              class = "dcc_template_error")
  }
  wb <- build_plan_workbook(language)
  openxlsx2::wb_save(wb, path, overwrite = FALSE)
  invisible(normalizePath(path, mustWork = TRUE))
}
