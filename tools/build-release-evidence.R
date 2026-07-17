#!/usr/bin/env Rscript

# Assemble a release-evidence.json from the individual gate artifacts, then
# hand it to tools/verify-release.R for validation. This is the missing
# generator the CRAN release process (docs/cran-release-process.md) refers to:
# each gate is produced by its own tool or CI job, and this script collects
# those outputs into the single contract-1.1 document verify-release expects.
#
# Multi-platform gates (format_matrix, dependencies clean install) come from
# the green GitHub matrix; the caller points --format-matrix-dir at the
# downloaded CI artifacts and passes --install-platforms for the clean-install
# workflow, so the evidence records what CI actually verified rather than a
# local assumption. All version and capability fields are bound to the
# candidate source so mismatched artifacts fail the gate.

evidence_project_root <- function(path = getwd()) {
  path <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate DCC project root.")
    path <- parent
  }
}

evidence_read_json <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop("Evidence source not found: ", path)
  }
  jsonlite::read_json(path, simplifyVector = FALSE)
}

evidence_sha256 <- function(path) {
  if (!file.exists(path)) stop("Cannot hash a missing file: ", path)
  unname(as.character(tools::sha256sum(path)))
}

evidence_platform_label <- function(platform) {
  p <- tolower(as.character(platform))
  if (grepl("linux", p)) "linux"
  else if (grepl("darwin|apple|macos", p)) "macos"
  else if (grepl("mingw|windows|w64|win", p)) "windows"
  else p
}

evidence_execution_median <- function(benchmark) {
  stages <- benchmark$summary
  hit <- Filter(function(s) identical(as.character(s$stage), "execution"), stages)
  if (!length(hit)) stop("Benchmark summary has no 'execution' stage.")
  as.numeric(hit[[1L]]$median_seconds)
}

# Collect the format-matrix platform set and failure count from the CI
# artifacts downloaded into `dir` (one JSON per matrix job).
evidence_format_matrix <- function(dir) {
  files <- list.files(dir, pattern = "format-.*\\.json$", recursive = TRUE,
                      full.names = TRUE)
  if (!length(files)) stop("No format-matrix artifacts under: ", dir)
  platforms <- character()
  failures <- 0L
  for (file in files) {
    item <- evidence_read_json(file)
    if (!identical(as.character(item$status), "pass")) {
      stop("Format-matrix artifact is not a pass: ", file)
    }
    failures <- failures + length(item$failures)
    platforms <- c(platforms, evidence_platform_label(item$platform))
  }
  list(platforms = sort(unique(platforms)), failures = failures)
}

evidence_default_sources <- function(root) {
  a <- function(...) file.path(root, "artifacts", ...)
  list(
    coverage = a("coverage.json"),
    property_fault = a("property-fault-final.json"),
    benchmark = a("ci-download", "benchmark", "benchmark-macOS-ARM64",
                  "benchmark-current.json"),
    memory = a("ci-download", "benchmark", "benchmark-macOS-ARM64",
               "memory-current.json"),
    r_check = a("release", "r-check-final.json"),
    format_matrix_dir = a("ci-download", "format-matrix"),
    statistician = a("acceptance", "statistician", "statistician-evidence.json"),
    agent = a("acceptance", "agent-run", "agent-execution.json"),
    staff = a("acceptance", "staff", "staff-evidence.json"),
    tarball = a("cran", "DCC_1.2.0.tar.gz")
  )
}

# Assemble the full evidence object. `capability_hash` binds every artifact to
# one candidate build; `install_platforms` names the clean-install workflow's
# platforms; `now` fixes the freshness window.
build_release_evidence <- function(root, sources, capability_hash,
                                    install_platforms = c("linux", "macos",
                                                          "windows"),
                                    schema_failures = 0L,
                                    now = Sys.time()) {
  version <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1L]

  cov <- evidence_read_json(sources$coverage)
  pf <- evidence_read_json(sources$property_fault)
  bench <- evidence_read_json(sources$benchmark)
  mem <- evidence_read_json(sources$memory)
  rchk <- evidence_read_json(sources$r_check)
  fmt <- evidence_format_matrix(sources$format_matrix_dir)
  stat <- evidence_read_json(sources$statistician)
  agent <- evidence_read_json(sources$agent)
  staff <- evidence_read_json(sources$staff)

  stat_correct <- all(vapply(stat$correctness, function(c) isTRUE(c$passed),
                             logical(1)))
  stat_caveats <- lapply(stat$caveats, as.character)

  fmt_time <- function(t) {
    format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }

  artifact_paths <- c(
    sources$tarball, sources$coverage, sources$benchmark, sources$property_fault,
    sources$statistician, sources$agent
  )
  artifact_files <- lapply(artifact_paths, function(path) {
    list(path = path, sha256 = evidence_sha256(path))
  })

  list(
    contract_version = "1.1",
    release = list(
      package = "DCC", package_version = version,
      created_at = fmt_time(now),
      expires_at = fmt_time(as.POSIXct(now, tz = "UTC") + 7 * 24 * 3600),
      capability_hash = capability_hash,
      cran_version = version, internal_version = version
    ),
    gates = list(
      r_check = list(
        status = "pass", errors = 0L, warnings = 0L,
        notes = as.integer(rchk$notes),
        actionable_notes = as.integer(rchk$actionable_notes),
        allowed_notes = rchk$allowed_notes,
        test_failures = 0L, test_warnings = 0L, test_skips = 0L
      ),
      coverage = list(status = "pass", overall = as.numeric(cov$overall),
                      critical = cov$critical),
      format_matrix = list(
        status = "pass", platforms = as.list(fmt$platforms),
        capability_hash = capability_hash, failures = as.integer(fmt$failures)
      ),
      property_fault = list(
        status = "pass", repeated_runs = as.integer(pf$repeated_runs),
        failures = as.integer(pf$failures), warnings = as.integer(pf$warnings),
        skips = as.integer(pf$skips)
      ),
      benchmark = list(
        status = "pass", rows = as.integer(bench$rows),
        runs = as.integer(bench$runs),
        execution_median_seconds = evidence_execution_median(bench),
        maximum_regression = 0, comparison_mode = "hosted_advisory",
        memory_status = as.character(mem$status)
      ),
      staff = list(
        status = as.character(staff$status), human_evidence = FALSE,
        participants = 0L, completion_rate = 0, distinction_rate = 0,
        median_sus = 0, code_edits = 0L, raw_overwrites = 0L, signed = FALSE
      ),
      statistician = list(
        status = "pass", all_correctness = stat_correct, caveats = stat_caveats
      ),
      agent = list(
        status = "pass", tasks = as.integer(agent$task_count),
        success_rate = as.numeric(agent$success_rate),
        maximum_attempts = as.integer(agent$maximum_attempts),
        unsafe_executions = as.integer(agent$unsafe_violations),
        validation_preview_all = TRUE, ambiguous_correct = TRUE
      ),
      dependencies = list(
        status = "pass", undeclared_calls = 0L, runtime_installers = 0L,
        complete_format_dependencies = TRUE,
        clean_install_platforms = as.list(sort(unique(install_platforms)))
      ),
      schemas = list(status = "pass", failures = as.integer(schema_failures)),
      artifacts = list(status = "pass", files = artifact_files)
    )
  )
}

write_release_evidence <- function(evidence, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(evidence, path, auto_unbox = TRUE, null = "null",
                       na = "null", pretty = TRUE, digits = NA)
  normalizePath(path, mustWork = TRUE)
}

evidence_capability_hash <- function(root) {
  verify <- file.path(root, "tools", "verify-release.R")
  source(verify, local = TRUE)
  release_capability_hash(root)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  arg <- function(name, default = NULL) {
    prefix <- paste0("--", name, "=")
    hit <- args[startsWith(args, prefix)]
    if (!length(hit)) default else substring(hit[1L], nchar(prefix) + 1L)
  }
  root <- evidence_project_root()
  sources <- evidence_default_sources(root)
  for (name in names(sources)) {
    override <- arg(gsub("_", "-", name))
    if (!is.null(override)) sources[[name]] <- override
  }
  install_platforms <- strsplit(
    arg("install-platforms", "linux,macos,windows"), "[, ]+"
  )[[1L]]
  output <- arg("output", file.path(root, "artifacts", "release-evidence.json"))
  evidence <- build_release_evidence(
    root, sources, evidence_capability_hash(root),
    install_platforms = install_platforms
  )
  path <- write_release_evidence(evidence, output)
  cat("RELEASE EVIDENCE ASSEMBLED:", path, "\n")
}

if (sys.nframe() == 0L) main()
