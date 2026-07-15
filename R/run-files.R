new_run_id <- function() {
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%OS3", tz = "UTC")
  candidate <- basename(tempfile(
    pattern = paste0("dcc-", stamp, "-", Sys.getpid(), "-")
  ))
  gsub("[^0-9A-Za-z]", "", candidate)
}

new_run_staging <- function(output_dir, run_id) {
  if (file.exists(output_dir)) {
    dcc_abort("Output already exists: ", output_dir,
              class = "dcc_run_error")
  }
  parent <- dirname(output_dir)
  if (!dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
    dcc_abort("Could not create output parent directory: ", parent,
              class = "dcc_run_error")
  }
  path <- paste0(output_dir, ".staging-", run_id)
  if (file.exists(path) ||
      !dir.create(path, recursive = FALSE, showWarnings = FALSE)) {
    dcc_abort("Could not create run staging directory: ", path,
              class = "dcc_run_error")
  }
  path
}

publish_run <- function(staging, output_dir, status, run_id) {
  target <- switch(
    status,
    success = output_dir,
    preview = output_dir,
    partial_failure = paste0(output_dir, ".partial-", run_id),
    failed = paste0(output_dir, ".failed-", run_id),
    dcc_abort("Unknown run publication status: ", status,
              class = "dcc_run_error")
  )
  if (file.exists(target)) {
    dcc_abort("Output already exists: ", target, class = "dcc_run_error")
  }
  if (!file.rename(staging, target)) {
    dcc_abort("Could not publish run directory: ", target,
              class = "dcc_run_error")
  }
  target
}

json_quote <- function(x) {
  x <- enc2utf8(as.character(x %||% ""))
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  paste0('"', x, '"')
}

write_failed_run <- function(staging, run_id, mode, error) {
  fields <- c(
    paste0('"run_id":', json_quote(run_id)),
    paste0('"status":"failed"'),
    paste0('"mode":', json_quote(mode)),
    paste0('"error_class":', json_quote(class(error)[1L])),
    paste0('"message":', json_quote(conditionMessage(error)))
  )
  writeLines(paste0("{", paste(fields, collapse = ","), "}"),
             file.path(staging, "run.json"), useBytes = TRUE)
  writeLines(c(
    "DCC run summary",
    paste0("run_id: ", run_id),
    "status: failed",
    paste0("mode: ", mode),
    paste0("error_class: ", class(error)[1L]),
    paste0("message: ", conditionMessage(error))
  ), file.path(staging, "run-summary.txt"), useBytes = TRUE)
}

published_paths <- function(paths, staging, target) {
  if (!length(paths)) return(paths)
  paste0(target, substring(paths, nchar(staging) + 1L))
}
