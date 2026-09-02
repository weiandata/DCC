#!/usr/bin/env Rscript

# Maintainer-only: regenerate the bundled workbook template in the source tree.
# Never runs during installation or `R CMD check`; requires devtools.

main <- function() {
  devtools::load_all(quiet = TRUE)
  path <- file.path("inst", "templates", "DCC-cleaning-plan.xlsx")
  if (file.exists(path)) unlink(path)
  dcc_template(path, language = "zh-CN")
}

# Only acts when run directly (Rscript). `source()` just defines main().
if (sys.nframe() == 0L) main()
