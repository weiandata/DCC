#!/usr/bin/env Rscript

coverage_area_patterns <- function() {
  c(
    import = "/(import|formats|dcc_read|encoding|compression|spreadsheet-structure)[.]R$",
    validation = "/validate[.]R$",
    rules = "/rules[.]R$",
    execution = "/execute[.]R$",
    audit = "/(execute|reconcile|provenance|trace)[.]R$",
    rerun = "/rerun[.]R$",
    `report-model` = "/report-model[.]R$"
  )
}

coverage_area_summary <- function(detail) {
  if (!all(c("filename", "value") %in% names(detail))) {
    stop("Coverage detail requires filename and value columns.")
  }
  filename <- gsub("\\\\", "/", as.character(detail$filename))
  patterns <- coverage_area_patterns()
  values <- lapply(patterns, function(pattern) {
    hit <- grepl(pattern, paste0("/", filename))
    if (!any(hit)) return(NA_real_)
    100 * mean(as.numeric(detail$value[hit]) > 0)
  })
  names(values) <- names(patterns)
  values
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  output <- if (length(args)) args[1L] else "artifacts/coverage.json"
  html <- if (length(args) >= 2L) args[2L] else "artifacts/coverage.html"
  if (!requireNamespace("covr", quietly = TRUE)) stop("Install covr to measure coverage.")
  old_source <- Sys.getenv("DCC_SOURCE_ROOT", unset = NA_character_)
  on.exit({
    if (is.na(old_source)) Sys.unsetenv("DCC_SOURCE_ROOT") else
      Sys.setenv(DCC_SOURCE_ROOT = old_source)
  }, add = TRUE)
  Sys.setenv(DCC_SOURCE_ROOT = normalizePath(getwd(), mustWork = TRUE))
  coverage <- covr::package_coverage(type = "tests", quiet = FALSE)
  detail <- as.data.frame(coverage)
  overall <- as.numeric(covr::percent_coverage(coverage))
  critical <- coverage_area_summary(detail)
  values <- as.numeric(unlist(critical, use.names = FALSE))
  pass <- is.finite(overall) && overall >= 90 &&
    length(values) == 7L && all(is.finite(values)) && all(values >= 95)
  evidence <- list(
    contract_version = "1.0", status = if (pass) "pass" else "fail",
    overall = overall, critical = critical,
    thresholds = list(overall = 90, critical = 95)
  )
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  detail_path <- paste0(tools::file_path_sans_ext(output), ".details.csv")
  utils::write.csv(detail, detail_path, row.names = FALSE, na = "")
  jsonlite::write_json(
    evidence, output, auto_unbox = TRUE, null = "null", na = "null",
    pretty = TRUE, digits = NA
  )
  dir.create(dirname(html), recursive = TRUE, showWarnings = FALSE)
  covr::report(coverage, file = html, browse = FALSE)
  if (!pass) {
    print(evidence)
    cat("COVERAGE: FAIL\n")
    quit(status = 1L)
  }
  cat(sprintf("COVERAGE: PASS (overall %.2f%%)\n", overall))
}

if (sys.nframe() == 0L) main()
