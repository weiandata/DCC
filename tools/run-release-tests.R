#!/usr/bin/env Rscript

argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  output <- argument(args, "output", "artifacts/release-tests.json")
  filter <- argument(args, "filter", NULL)
  runs <- as.integer(argument(args, "runs", "1"))
  if (is.na(runs) || runs < 1L) stop("--runs must be positive.")
  results <- lapply(seq_len(runs), function(run) {
    test <- testthat::test_local(filter = filter, reporter = "silent",
                                stop_on_failure = FALSE)
    table <- as.data.frame(test)
    data.frame(
      run = run,
      failures = sum(table$failed) + sum(as.logical(table$error)),
      warnings = sum(table$warning),
      skips = sum(as.logical(table$skipped)),
      expectations = sum(table$nb),
      seconds = sum(table$real),
      stringsAsFactors = FALSE
    )
  })
  results <- do.call(rbind, results)
  pass <- all(results$failures == 0L) && all(results$warnings == 0L) &&
    all(results$skips == 0L)
  evidence <- list(
    contract_version = "1.0", status = if (pass) "pass" else "fail",
    filter = filter %||% "all", repeated_runs = runs,
    failures = sum(results$failures), warnings = sum(results$warnings),
    skips = sum(results$skips), runs = results
  )
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    evidence, output, auto_unbox = TRUE, dataframe = "rows", null = "null",
    na = "null", pretty = TRUE, digits = NA
  )
  if (!pass) {
    print(results, row.names = FALSE)
    cat("RELEASE TESTS: FAIL\n")
    quit(status = 1L)
  }
  cat(sprintf("RELEASE TESTS: PASS (%d run(s))\n", runs))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

if (sys.nframe() == 0L) main()
