#!/usr/bin/env Rscript

r_check_argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

resolve_r_check_log <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop("Provide one existing check log or check directory.")
  }
  if (!dir.exists(path)) return(normalizePath(path, mustWork = TRUE))
  logs <- list.files(path, pattern = "^00check[.]log$", recursive = TRUE,
                     full.names = TRUE)
  if (length(logs) != 1L) {
    stop("Check directory must contain exactly one 00check.log.")
  }
  normalizePath(logs, mustWork = TRUE)
}

r_check_status_count <- function(status, label) {
  pattern <- paste0("([0-9]+)[[:space:]]+", label, "S?")
  match <- regexec(pattern, status, perl = TRUE)
  parts <- regmatches(status, match)[[1L]]
  if (length(parts) < 2L) 0L else as.integer(parts[2L])
}

exact_first_submission_note <- function(lines, start) {
  later <- which(seq_along(lines) > start & grepl("^\\* checking ", lines))
  end <- if (length(later)) later[1L] - 1L else length(lines)
  body <- if (end > start) trimws(lines[seq.int(start + 1L, end)]) else
    character()
  body <- body[nzchar(body)]
  isTRUE(sum(grepl("^Maintainer:", body)) == 1L) &&
    isTRUE(sum(body == "New submission") == 1L) &&
    all(grepl("^Maintainer:", body) | body == "New submission")
}

classify_r_check_log <- function(path, test_failures = 0L,
                                 test_warnings = 0L, test_skips = 0L) {
  log <- resolve_r_check_log(path)
  lines <- readLines(log, warn = FALSE, encoding = "UTF-8")
  status_lines <- grep("^Status:", lines, value = TRUE)
  if (!length(status_lines)) stop("Check log has no final Status line.")
  status_line <- status_lines[length(status_lines)]
  errors <- r_check_status_count(status_line, "ERROR")
  warnings <- r_check_status_count(status_line, "WARNING")
  notes <- r_check_status_count(status_line, "NOTE")

  note_headers <- which(startsWith(lines, "* checking ") &
                          endsWith(lines, " NOTE"))
  incoming <- which(startsWith(
    lines, "* checking CRAN incoming feasibility"
  ) & endsWith(lines, " NOTE"))
  exact <- incoming[vapply(
    incoming, function(index) exact_first_submission_note(lines, index),
    logical(1)
  )]
  allowed_notes <- if (length(exact)) "cran_new_submission" else character()
  actionable_notes <- max(notes - length(allowed_notes), 0L)
  if (notes != length(note_headers)) {
    actionable_notes <- max(actionable_notes, 1L)
  }
  test_counts <- suppressWarnings(as.integer(c(
    test_failures, test_warnings, test_skips
  )))
  if (length(test_counts) != 3L || anyNA(test_counts) || any(test_counts < 0L)) {
    stop("Test counts must be three non-negative integers.")
  }
  pass <- errors == 0L && warnings == 0L && actionable_notes == 0L &&
    all(test_counts == 0L)
  list(
    contract_version = "1.0", status = if (pass) "pass" else "fail",
    errors = errors, warnings = warnings, notes = notes,
    actionable_notes = as.integer(actionable_notes),
    allowed_notes = allowed_notes,
    test_failures = test_counts[1L], test_warnings = test_counts[2L],
    test_skips = test_counts[3L], log = log
  )
}

write_r_check_evidence <- function(result, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  value <- result
  value$allowed_notes <- as.list(value$allowed_notes)
  jsonlite::write_json(
    value, path, auto_unbox = TRUE, null = "null", na = "null",
    pretty = TRUE
  )
  normalizePath(path, mustWork = TRUE)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  log <- r_check_argument(args, "log")
  output <- r_check_argument(args, "output", "artifacts/r-check.json")
  if (is.null(log)) stop("Usage: classify-r-check.R --log=PATH [--output=FILE]")
  result <- classify_r_check_log(log)
  write_r_check_evidence(result, output)
  if (!identical(result$status, "pass")) {
    print(result[c("errors", "warnings", "notes", "actionable_notes",
                   "allowed_notes")])
    cat("R CHECK EVIDENCE: FAIL\n")
    quit(status = 1L)
  }
  cat("R CHECK EVIDENCE: PASS\n")
}

if (sys.nframe() == 0L) main()
