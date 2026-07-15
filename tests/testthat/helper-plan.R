plan_fixture <- function(source = tempfile(fileext = ".csv")) {
  if (!file.exists(source)) {
    writeLines(c("sid,score", "S1,90", "S2,150"), source)
  }
  new_dcc_plan(
    project = list(
      template_version = "1.0",
      project_id = "demo",
      project_name = "DCC 示例项目",
      language = "zh-CN"
    ),
    source = list(
      path = source,
      format = "csv",
      encoding = "UTF-8"
    ),
    columns = data.frame(
      source_name = c("sid", "score"),
      name = c("sid", "score"),
      type = c("character", "double"),
      role = c("id", "score"),
      required = c(TRUE, TRUE),
      label = c("受访者编号", "得分"),
      stringsAsFactors = FALSE
    ),
    rules = data.frame(
      id = "R001", type = "range", variable = "score",
      parameters = '{"min":0,"max":100}', severity = "warn",
      stringsAsFactors = FALSE
    ),
    actions = data.frame(
      rule_id = "R001", action = "set_na", parameters = "{}",
      stringsAsFactors = FALSE
    ),
    outputs = data.frame(
      key = c("report_language", "cleaned_format"),
      value = c("zh-CN", "csv"), stringsAsFactors = FALSE
    )
  )
}

write_plan_workbook <- function(plan = plan_fixture(), path =
                                  tempfile(fileext = ".xlsx")) {
  dcc_template(path, language = plan$project$language)
  wb <- openxlsx2::wb_load(path)
  for (section in c("project", "source")) {
    tab <- data.frame(
      key = names(plan[[section]]),
      value = vapply(plan[[section]], as.character, character(1)),
      stringsAsFactors = FALSE
    )
    wb <- openxlsx2::wb_add_data(wb, section, tab, start_row = 3,
                                 col_names = FALSE)
  }
  for (section in names(plan_table_contracts())) {
    tab <- as.data.frame(plan[[section]], stringsAsFactors = FALSE)
    if (nrow(tab)) {
      wb <- openxlsx2::wb_add_data(wb, section, tab, start_row = 3,
                                   col_names = FALSE)
    }
  }
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  path
}

write_plan_json <- function(plan = plan_fixture(), path =
                              tempfile(fileext = ".json")) {
  jsonlite::write_json(unclass(plan), path, auto_unbox = TRUE,
                       dataframe = "rows",
                       null = "null", na = "null", pretty = TRUE)
  path
}
