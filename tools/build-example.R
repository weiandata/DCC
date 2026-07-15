#!/usr/bin/env Rscript

devtools::load_all(quiet = TRUE)
root <- file.path("examples", "strict-excel-project")
json_path <- file.path(root, "DCC-cleaning-plan.json")
xlsx_path <- file.path(root, "DCC-cleaning-plan.xlsx")
plan <- dcc_read_plan(json_path)
if (file.exists(xlsx_path)) unlink(xlsx_path)
dcc_template(xlsx_path, language = plan$project$language)
wb <- openxlsx2::wb_load(xlsx_path)
defaults <- plan_template_defaults(plan$project$language)
for (section in c("project", "source")) {
  tab <- defaults[[section]]
  supplied <- plan[[section]]
  hit <- match(names(supplied), tab$key)
  tab$value[hit] <- vapply(supplied, as.character, character(1))
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
openxlsx2::wb_save(wb, xlsx_path, overwrite = TRUE)

