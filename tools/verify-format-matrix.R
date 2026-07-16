#!/usr/bin/env Rscript

`%||%` <- function(x, y) if (is.null(x)) y else x

find_project_root <- function(path = getwd()) {
  path <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate DCC project root.")
    path <- parent
  }
}

canonical_matrix_hash <- function(data) {
  data <- as.data.frame(data, check.names = FALSE, stringsAsFactors = FALSE)
  normalized <- lapply(data, function(column) {
    value <- as.character(column)
    value[is.na(column)] <- NA_character_
    value
  })
  normalized <- as.data.frame(normalized, check.names = FALSE,
                              stringsAsFactors = FALSE)
  payload <- jsonlite::toJSON(
    normalized, dataframe = "rows", auto_unbox = TRUE, na = "null",
    null = "null", digits = NA
  )
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(enc2utf8(payload)), path)
  unname(as.character(tools::sha256sum(path)))
}

read_fixture <- function(record, root) {
  options <- record$options %||% list()
  arguments <- c(list(
    path = file.path(root, record$path), format = record$format,
    encoding = record$declared_encoding %||% record$encoding %||% "auto"
  ), options)
  do.call(DCC::dcc_read, arguments)
}

main <- function() {
  root <- find_project_root()
  if (!requireNamespace("DCC", quietly = TRUE)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("Install DCC first, or install pkgload to verify from source.")
    }
    pkgload::load_all(root, quiet = TRUE)
  }
  args <- commandArgs(trailingOnly = TRUE)
  output_arg <- grep("^--output=", args, value = TRUE)
  output_path <- if (length(output_arg)) sub("^--output=", "", output_arg[1L]) else ""
  manifest_path <- file.path(root, "tests", "fixtures", "formats", "manifest.json")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  capabilities <- DCC::dcc_capabilities()$formats
  results <- list()
  failures <- character()

  for (record in manifest$fixtures) {
    key <- if (nzchar(record$path %||% "")) record$path else
      paste(record$format, record$encoding, record$compression, sep = ":")
    actual_level <- as.character(
      capabilities$status[match(record$format, capabilities$format)]
    )
    if (!identical(actual_level, record$capability_level)) {
      failures <- c(failures, paste0(
        key, ": capability level drifted from ", record$capability_level,
        " to ", actual_level
      ))
    }
    if (identical(record$fixture_status, "external_required")) {
      if (identical(actual_level, "Stable")) {
        failures <- c(failures, paste0(
          key, ": Stable capability lacks committed runnable evidence"
        ))
      }
      results[[length(results) + 1L]] <- list(
        fixture = key, status = "external_required", format = record$format,
        capability_level = actual_level, reason = record$reason
      )
      next
    }

    path <- file.path(root, record$path)
    if (!file.exists(path)) {
      failures <- c(failures, paste0(key, ": fixture missing"))
      next
    }
    file_hash <- unname(as.character(tools::sha256sum(path)))
    if (!identical(file_hash, record$file_sha256)) {
      failures <- c(failures, paste0(key, ": file SHA-256 mismatch"))
      next
    }
    outcome <- tryCatch({
      data <- read_fixture(record, root)
      hash <- canonical_matrix_hash(data$data)
      if (!identical(hash, record$expected_canonical_hash)) {
        stop("canonical SHA-256 mismatch")
      }
      expected_missing <- as.integer(record$expected_missing_states %||% 0L)
      if (!identical(nrow(DCC::dcc_missing_states(data)), expected_missing)) {
        stop("missing-state count mismatch")
      }
      labels <- record$expected_labels %||% list()
      if (length(labels)) {
        dictionary <- DCC::dcc_dictionary(data)
        for (name in names(labels)) {
          actual <- as.character(dictionary$label[dictionary$name == name])
          if (!identical(actual, as.character(labels[[name]]))) {
            stop("label mismatch for ", name)
          }
        }
      }
      list(status = "pass", canonical_hash = hash, message = "")
    }, error = function(error) {
      list(status = "fail", canonical_hash = NA_character_,
           message = conditionMessage(error))
    })
    if (outcome$status == "fail") {
      failures <- c(failures, paste0(key, ": ", outcome$message))
    }
    results[[length(results) + 1L]] <- c(
      list(fixture = key, format = record$format,
           capability_level = actual_level), outcome
    )
  }

  evidence <- list(
    contract_version = "1.0",
    platform = paste(R.version$platform, R.version$arch, sep = "/"),
    r_version = R.version.string,
    dcc_version = as.character(utils::packageVersion("DCC")),
    manifest_sha256 = unname(as.character(tools::sha256sum(manifest_path))),
    generated_fixture_results = results, failures = failures,
    status = if (length(failures)) "fail" else "pass"
  )
  if (nzchar(output_path)) {
    if (!grepl("^/", output_path)) output_path <- file.path(root, output_path)
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(evidence, output_path, auto_unbox = TRUE,
                         null = "null", na = "null", pretty = TRUE)
  }
  if (length(failures)) {
    cat("FORMAT MATRIX: FAIL\n", paste0("- ", failures, collapse = "\n"),
        "\n", sep = "")
    quit(status = 1L)
  }
  passed <- sum(vapply(results, function(result) {
    identical(result$status, "pass")
  }, logical(1)))
  external <- sum(vapply(results, function(result) {
    identical(result$status, "external_required")
  }, logical(1)))
  cat("FORMAT MATRIX: PASS (", passed, " generated; ", external,
      " external evidence required)\n", sep = "")
}

main()
