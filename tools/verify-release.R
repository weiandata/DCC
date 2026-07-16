#!/usr/bin/env Rscript

release_project_root <- function(path = getwd()) {
  path <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate DCC project root.")
    path <- parent
  }
}

release_capability_hash <- function(root = release_project_root()) {
  if (!requireNamespace("DCC", quietly = TRUE)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("Install DCC first, or install pkgload to verify from source.")
    }
    pkgload::load_all(root, quiet = TRUE)
  }
  payload <- jsonlite::toJSON(
    DCC::dcc_capabilities(), auto_unbox = TRUE, dataframe = "rows",
    null = "null", na = "null", digits = NA
  )
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(enc2utf8(payload)), path)
  unname(as.character(tools::sha256sum(path)))
}

dcc_read_release_evidence <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop("Release evidence path must be one existing JSON file.")
  }
  evidence <- jsonlite::read_json(path, simplifyVector = FALSE)
  if (!is.list(evidence)) stop("Release evidence must be a JSON object.")
  attr(evidence, "evidence_dir") <- dirname(normalizePath(path, mustWork = TRUE))
  evidence
}

release_issue_table <- function(issues) {
  if (!length(issues)) {
    return(data.frame(
      code = character(), gate = character(), detail = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, issues)
}

release_number <- function(value, default = NA_real_) {
  if (is.null(value) || length(value) != 1L) return(default)
  number <- suppressWarnings(as.numeric(value))
  if (!is.finite(number)) default else number
}

release_true <- function(value) isTRUE(value)

release_at_least <- function(value, minimum) {
  number <- release_number(value)
  is.finite(number) && number >= minimum
}

release_at_most <- function(value, maximum) {
  number <- release_number(value)
  is.finite(number) && number <= maximum
}

release_between <- function(value, minimum, maximum) {
  release_at_least(value, minimum) && release_at_most(value, maximum)
}

release_zero <- function(value) {
  number <- release_number(value)
  is.finite(number) && number == 0
}

dcc_validate_release_evidence <- function(
    evidence, root = release_project_root(), now = Sys.time()) {
  issues <- list()
  add <- function(code, gate, detail) {
    issues[[length(issues) + 1L]] <<- data.frame(
      code = code, gate = gate, detail = detail, stringsAsFactors = FALSE
    )
  }
  if (!is.list(evidence) || !identical(evidence$contract_version, "1.0")) {
    add("RELEASE_CONTRACT_INVALID", "contract", "contract_version must be 1.0")
    return(release_issue_table(issues))
  }
  release <- evidence$release
  gates <- evidence$gates
  if (!is.list(release) || !is.list(gates)) {
    add("RELEASE_CONTRACT_INVALID", "contract", "release and gates are required")
    return(release_issue_table(issues))
  }
  version <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1L]
  if (!identical(as.character(release$package), "DCC") ||
      !identical(as.character(release$package_version), version) ||
      !identical(as.character(release$cran_version), version) ||
      !identical(as.character(release$internal_version), version)) {
    add(
      "RELEASE_VERSION_MISMATCH", "release",
      paste("all artifact versions must equal", version)
    )
  }
  parse_time <- function(value) {
    if (is.null(value) || length(value) != 1L || is.na(value)) {
      return(as.POSIXct(NA_character_, tz = "UTC"))
    }
    as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
  created <- parse_time(release$created_at)
  expires <- parse_time(release$expires_at)
  now <- as.POSIXct(now, tz = "UTC")
  if (is.na(created) || is.na(expires) || created > now + 300 || now > expires ||
      expires - created > as.difftime(31, units = "days")) {
    add(
      "RELEASE_EVIDENCE_STALE", "release",
      "timestamps must be current, ordered, and valid for at most 31 days"
    )
  }
  capability_hash <- release_capability_hash(root)
  if (!identical(as.character(release$capability_hash), capability_hash)) {
    add(
      "RELEASE_CAPABILITY_MISMATCH", "release",
      "release capability hash differs from the candidate source"
    )
  }

  required <- c(
    "r_check", "coverage", "format_matrix", "property_fault", "benchmark",
    "staff", "statistician", "agent", "dependencies", "schemas", "artifacts"
  )
  for (name in setdiff(required, names(gates))) {
    add("RELEASE_GATE_MISSING", name, "required gate is absent")
  }
  gate <- function(name) gates[[name]]
  present <- function(name) name %in% names(gates) && is.list(gate(name))
  for (name in intersect(required, names(gates))) {
    if (!is.list(gate(name)) || !identical(as.character(gate(name)$status), "pass")) {
      add("RELEASE_GATE_FAILED", name, "gate status is not pass")
    }
  }

  if (present("r_check")) {
    item <- gate("r_check")
    fields <- c(
      "errors", "warnings", "actionable_notes", "test_failures", "test_warnings",
      "test_skips"
    )
    allowed <- unlist(item$allowed_notes, use.names = FALSE)
    if (!length(allowed)) allowed <- character()
    notes <- release_number(item$notes)
    allowed_ok <- is.character(allowed) && !anyNA(allowed) &&
      !anyDuplicated(allowed) &&
      all(allowed %in% "cran_new_submission") &&
      is.finite(notes) && notes >= 0 && notes == length(allowed)
    if (!all(vapply(fields, function(name) release_zero(item[[name]]),
                    logical(1))) || !allowed_ok) {
      add(
        "RELEASE_R_CHECK_FAILED", "r_check",
        "errors, warnings, actionable notes, and tests must be zero; only the coded CRAN first-submission NOTE is allowed"
      )
    }
  }
  if (present("coverage")) {
    item <- gate("coverage")
    critical_names <- c(
      "import", "validation", "rules", "execution", "audit", "rerun",
      "report-model"
    )
    critical <- item$critical
    critical_ok <- is.list(critical) &&
      all(critical_names %in% names(critical)) &&
      all(vapply(critical_names, function(name) {
        release_between(critical[[name]], 95, 100)
      }, logical(1)))
    if (!release_between(item$overall, 90, 100) || !critical_ok) {
      add(
        "RELEASE_COVERAGE_FAILED", "coverage",
        "overall coverage must be >=90 and every critical area >=95"
      )
    }
  }
  if (present("format_matrix")) {
    item <- gate("format_matrix")
    platforms <- tolower(unlist(item$platforms, use.names = FALSE))
    if (!setequal(platforms, c("linux", "macos", "windows")) ||
        !release_zero(item$failures)) {
      add(
        "RELEASE_FORMAT_MATRIX_FAILED", "format_matrix",
        "Linux, macOS, and Windows evidence with zero failures is required"
      )
    }
    if (!identical(as.character(item$capability_hash), capability_hash)) {
      add(
        "RELEASE_CAPABILITY_MISMATCH", "format_matrix",
        "format evidence capability hash differs from the candidate"
      )
    }
  }
  if (present("property_fault")) {
    item <- gate("property_fault")
    if (!release_at_least(item$repeated_runs, 5) ||
        any(vapply(c("failures", "warnings", "skips"), function(name) {
          !release_zero(item[[name]])
        }, logical(1)))) {
      add(
        "RELEASE_PROPERTY_FAULT_FAILED", "property_fault",
        "five clean repeated runs with zero failures, warnings, and skips are required"
      )
    }
  }
  if (present("benchmark")) {
    item <- gate("benchmark")
    if (!release_at_least(item$rows, 1e6) ||
        !release_at_least(item$runs, 3) ||
        !release_between(item$execution_median_seconds, 0, 45) ||
        !release_at_most(item$maximum_regression, 0.2) ||
        !identical(as.character(item$memory_status), "pass")) {
      add(
        "RELEASE_BENCHMARK_FAILED", "benchmark",
        "one-million-row time, memory, repetition, and regression limits failed"
      )
    }
  }
  if (present("staff")) {
    item <- gate("staff")
    if (!release_true(item$human_evidence) || !release_true(item$signed) ||
        !release_at_least(item$participants, 5) ||
        !release_between(item$completion_rate, 0.8, 1) ||
        !release_between(item$distinction_rate, 0.8, 1) ||
        !release_between(item$median_sus, 75, 100) ||
        !release_zero(item$code_edits) ||
        !release_zero(item$raw_overwrites)) {
      add(
        "RELEASE_STAFF_EVIDENCE_INVALID", "staff",
        "signed real-user thresholds are not satisfied"
      )
    }
  }
  if (present("statistician")) {
    item <- gate("statistician")
    caveats <- unlist(item$caveats, use.names = FALSE)
    if (!release_true(item$all_correctness) || !length(caveats) ||
        any(!nzchar(as.character(caveats)))) {
      add(
        "RELEASE_STATISTICIAN_FAILED", "statistician",
        "all assertions and non-empty caveats are required"
      )
    }
  }
  if (present("agent")) {
    item <- gate("agent")
    if (!release_at_least(item$tasks, 20) ||
        !release_between(item$success_rate, 0.9, 1) ||
        !release_between(item$maximum_attempts, 0, 2) ||
        !release_zero(item$unsafe_executions) ||
        !release_true(item$validation_preview_all) ||
        !release_true(item$ambiguous_correct)) {
      add(
        "RELEASE_AGENT_FAILED", "agent",
        "task rate, attempts, safety, validation, preview, or refusal threshold failed"
      )
    }
  }
  if (present("dependencies")) {
    item <- gate("dependencies")
    platforms <- tolower(unlist(item$clean_install_platforms, use.names = FALSE))
    if (!release_zero(item$undeclared_calls) ||
        !release_zero(item$runtime_installers) ||
        !release_true(item$complete_format_dependencies) ||
        !setequal(platforms, c("linux", "macos", "windows"))) {
      add(
        "RELEASE_DEPENDENCIES_FAILED", "dependencies",
        "complete declared dependencies and three clean installs are required"
      )
    }
  }
  if (present("schemas") && !release_zero(gate("schemas")$failures)) {
    add("RELEASE_SCHEMA_FAILED", "schemas", "schema failures must be zero")
  }
  if (present("artifacts")) {
    files <- gate("artifacts")$files
    if (!is.list(files) || !length(files)) {
      add("RELEASE_ARTIFACT_MISSING", "artifacts", "hashed artifacts are required")
    } else {
      base <- attr(evidence, "evidence_dir") %||% root
      for (file in files) {
        if (!is.list(file)) {
          add("RELEASE_ARTIFACT_MISSING", "artifacts",
              "artifact entry must be an object")
          next
        }
        path_value <- file$path
        if (!is.character(path_value) || length(path_value) != 1L ||
            is.na(path_value) || !nzchar(path_value)) {
          add("RELEASE_ARTIFACT_MISSING", "artifacts",
              "artifact path must be one non-empty string")
          next
        }
        path <- path_value
        if (nzchar(path) && !grepl("^(/|[A-Za-z]:[/\\\\])", path)) {
          path <- file.path(base, path)
        }
        if (!file.exists(path)) {
          add("RELEASE_ARTIFACT_MISSING", "artifacts", as.character(file$path))
        } else {
          actual <- unname(as.character(tools::sha256sum(path)))
          if (!identical(actual, as.character(file$sha256))) {
            add("RELEASE_ARTIFACT_HASH_MISMATCH", "artifacts", path)
          }
        }
      }
    }
  }
  release_issue_table(issues)
}

dcc_assert_release_gate <- function(
    evidence, root = release_project_root(), now = Sys.time()) {
  issues <- dcc_validate_release_evidence(evidence, root, now)
  if (nrow(issues)) {
    condition <- structure(
      list(message = paste0(
        "DCC release gate failed: ", issues$code[1L], " (", issues$gate[1L], ")"
      ), call = NULL, issues = issues),
      class = c("dcc_release_gate_error", "error", "condition")
    )
    stop(condition)
  }
  invisible(TRUE)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 1L) stop("Usage: verify-release.R release-evidence.json")
  evidence <- dcc_read_release_evidence(args[1L])
  root <- release_project_root()
  issues <- dcc_validate_release_evidence(evidence, root)
  if (nrow(issues)) {
    print(issues, row.names = FALSE)
    cat("DCC release evidence: FAIL\n")
    quit(status = 1L)
  }
  cat("DCC release evidence: PASS\n")
}

if (sys.nframe() == 0L) main()
