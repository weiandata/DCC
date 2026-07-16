#!/usr/bin/env Rscript

memory_required_stages <- function() {
  c(
    "import", "canonicalization", "validation", "detection", "preview",
    "execution", "report_model", "staff", "statistical", "machine"
  )
}

memory_failure <- function(code, stage = NA_character_, detail = "") {
  data.frame(
    code = code, stage = stage, detail = detail, stringsAsFactors = FALSE
  )
}

check_memory_evidence <- function(records, minimum_rows = 1e6,
                                  maximum_bytes = 8 * 1024^3,
                                  maximum_bytes_per_cell = 256) {
  failures <- list()
  add <- function(code, stage = NA_character_, detail = "") {
    failures[[length(failures) + 1L]] <<-
      memory_failure(code, stage, detail)
  }
  required <- c(
    "stage", "rows", "columns", "input_bytes", "peak_memory_bytes",
    "correctness"
  )
  absent <- setdiff(required, names(records))
  if (length(absent)) {
    add("BENCHMARK_MEMORY_CONTRACT_INVALID", detail = paste(absent, collapse = ","))
  } else {
    missing_stages <- setdiff(memory_required_stages(), unique(records$stage))
    for (stage in missing_stages) add("BENCHMARK_STAGE_MISSING", stage)
    if (any(as.numeric(records$rows) < minimum_rows)) {
      add(
        "BENCHMARK_SCALE_INVALID",
        detail = paste("release evidence requires at least", minimum_rows, "rows")
      )
    }
    if (any(!as.logical(records$correctness)) || anyNA(records$correctness)) {
      add("BENCHMARK_CORRECTNESS_FAILED")
    }
    peaks <- as.numeric(records$peak_memory_bytes)
    bytes_per_cell <- peaks / pmax(
      as.numeric(records$rows) * as.numeric(records$columns), 1
    )
    bad_absolute <- which(!is.finite(peaks) | peaks > maximum_bytes)
    for (index in bad_absolute) {
      add(
        "BENCHMARK_MEMORY_LIMIT", as.character(records$stage[index]),
        sprintf("%.0f bytes exceeds %.0f", peaks[index], maximum_bytes)
      )
    }
    bad_growth <- which(
      !is.finite(bytes_per_cell) | bytes_per_cell > maximum_bytes_per_cell
    )
    for (index in bad_growth) {
      add(
        "BENCHMARK_MEMORY_GROWTH", as.character(records$stage[index]),
        sprintf("%.2f bytes/cell exceeds %.2f", bytes_per_cell[index],
                maximum_bytes_per_cell)
      )
    }
  }
  failure_table <- if (length(failures)) do.call(rbind, failures) else
    data.frame(code = character(), stage = character(), detail = character(),
               stringsAsFactors = FALSE)
  list(
    ok = nrow(failure_table) == 0L,
    maximum_peak_memory_bytes = if ("peak_memory_bytes" %in% names(records)) {
      max(as.numeric(records$peak_memory_bytes), na.rm = TRUE)
    } else NA_real_,
    maximum_bytes_per_cell = if (all(c("peak_memory_bytes", "rows", "columns") %in%
                                  names(records))) {
      max(as.numeric(records$peak_memory_bytes) / pmax(
        as.numeric(records$rows) * as.numeric(records$columns), 1
      ), na.rm = TRUE)
    } else NA_real_,
    failures = failure_table
  )
}

memory_argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  input <- memory_argument(args, "input", "artifacts/benchmark-current.json")
  output <- memory_argument(args, "output", "artifacts/memory-current.json")
  if (!file.exists(input)) stop("Benchmark evidence does not exist: ", input)
  evidence <- jsonlite::read_json(input, simplifyVector = TRUE)
  result <- check_memory_evidence(evidence$records)
  artifact <- list(
    contract_version = "1.0", generated_at = format(
      Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    source = normalizePath(input, mustWork = TRUE),
    rows = evidence$rows, columns = evidence$columns,
    maximum_peak_memory_bytes = result$maximum_peak_memory_bytes,
    maximum_bytes_per_cell = result$maximum_bytes_per_cell,
    status = if (result$ok) "pass" else "fail",
    failures = result$failures
  )
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    artifact, output, auto_unbox = TRUE, dataframe = "rows", na = "null",
    null = "null", pretty = TRUE, digits = NA
  )
  if (!result$ok) {
    print(result$failures, row.names = FALSE)
    cat("MEMORY: FAIL\n")
    quit(status = 1L)
  }
  cat(sprintf(
    "MEMORY: PASS (peak %.2f GiB; %.2f bytes/cell)\n",
    result$maximum_peak_memory_bytes / 1024^3,
    result$maximum_bytes_per_cell
  ))
}

if (sys.nframe() == 0L) main()
