#!/usr/bin/env Rscript

devtools::load_all(quiet = TRUE)
path <- file.path("inst", "templates", "DCC-cleaning-plan.xlsx")
if (file.exists(path)) unlink(path)
dcc_template(path, language = "zh-CN")

