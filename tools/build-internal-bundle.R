#!/usr/bin/env Rscript

find_project_root <- function(path = getwd()) {
  path <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate DCC project root.")
    path <- parent
  }
}

argument <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  substring(hit[1L], nchar(prefix) + 1L)
}

write_report <- function(path, value) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    value, path, auto_unbox = TRUE, dataframe = "rows", na = "null",
    null = "null", pretty = TRUE, digits = NA
  )
}

expected_archives <- function(lock) {
  packages <- lock$Packages
  stats::setNames(vapply(names(packages), function(package) {
    paste0(package, "_", packages[[package]]$Version, ".tar.gz")
  }, character(1)), names(packages))
}

download_archives <- function(packages, destination) {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  repos <- getOption("repos")
  if (!length(repos) || any(repos == "@CRAN@")) {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }
  result <- utils::download.packages(
    packages, destdir = destination, type = "source",
    repos = repos
  )
  invisible(result)
}

write_install_script <- function(path) {
  lines <- c(
    "args <- commandArgs(trailingOnly = TRUE)",
    "library_path <- if (length(args)) args[1L] else .libPaths()[1L]",
    "dir.create(library_path, recursive = TRUE, showWarnings = FALSE)",
    "repository <- normalizePath('repository', mustWork = TRUE)",
    "options(repos = c(DCC_INTERNAL = paste0('file://', repository)))",
    "install.packages('DCC', lib = library_path, dependencies = TRUE, type = 'source')",
    ".libPaths(c(library_path, .libPaths()))",
    "library(DCC)",
    "print(dcc_doctor())"
  )
  writeLines(lines, path, useBytes = TRUE)
}

write_license_inventory <- function(root, packages, path) {
  installed <- installed.packages(fields = c(
    "License", "License_is_FOSS", "License_restricts_use", "OS_type"
  ))
  dependencies <- data.frame(
    package = packages,
    version = installed[packages, "Version"],
    license = installed[packages, "License"],
    license_is_foss = installed[packages, "License_is_FOSS"],
    license_restricts_use = installed[packages, "License_restricts_use"],
    os_type = installed[packages, "OS_type"],
    stringsAsFactors = FALSE
  )
  description <- read.dcf(
    file.path(root, "DESCRIPTION"), fields = c("Package", "Version", "License")
  )
  inventory <- rbind(
    data.frame(
      package = description[1L, "Package"],
      version = description[1L, "Version"],
      license = description[1L, "License"],
      license_is_foss = "", license_restricts_use = "", os_type = "",
      stringsAsFactors = FALSE
    ),
    dependencies
  )
  utils::write.csv(inventory, path, row.names = FALSE, na = "")
}

write_checksums <- function(root) {
  normalized_root <- normalizePath(root, mustWork = TRUE)
  files <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  files <- files[file.info(files)$isdir %in% FALSE]
  files <- files[basename(files) != "SHA256SUMS"]
  relative <- substring(
    normalizePath(files, mustWork = TRUE), nchar(normalized_root) + 2L
  )
  hashes <- unname(as.character(tools::sha256sum(files)))
  writeLines(paste(hashes, gsub("\\\\", "/", relative)),
             file.path(root, "SHA256SUMS"), useBytes = TRUE)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  root <- find_project_root()
  source(file.path(root, "tools", "verify-dependencies.R"), local = TRUE)
  audit <- audit_dependencies(root)
  if (!audit$ok) stop("Dependency audit must pass before building a bundle.")
  version <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1L]
  output <- normalizePath(
    argument(args, "output", file.path(root, "artifacts", paste0(
      "DCC-", version, "-internal"
    ))),
    mustWork = FALSE
  )
  incomplete <- paste0(output, ".incomplete")
  if (dir.exists(output) || dir.exists(incomplete)) {
    stop("Bundle output already exists; choose a new --output path.")
  }
  source_cache <- argument(args, "source-cache", tempfile("dcc-source-cache-"))
  dir.create(source_cache, recursive = TRUE, showWarnings = FALSE)
  lock <- jsonlite::read_json(file.path(root, "renv.lock"), simplifyVector = FALSE)
  archives <- expected_archives(lock)
  if ("--download" %in% args) {
    download_archives(names(archives), source_cache)
  }
  available <- list.files(source_cache, pattern = "[.]tar[.]gz$", full.names = TRUE)
  missing <- archives[!file.exists(file.path(source_cache, archives))]
  if (length(missing)) {
    dir.create(incomplete, recursive = TRUE, showWarnings = FALSE)
    report <- list(
      contract_version = "1.0", status = "incomplete",
      contains_user_data = FALSE, package = "DCC", version = version,
      missing_source_archives = unname(missing),
      fix = "Populate --source-cache with the exact locked source archives or rerun with --download."
    )
    write_report(file.path(incomplete, "verification-report.json"), report)
    cat("INTERNAL BUNDLE: INCOMPLETE\n")
    cat(paste(unname(missing), collapse = "\n"), "\n")
    quit(status = 2L)
  }

  staging <- tempfile(paste0("DCC-", version, "-bundle-"))
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  repository <- file.path(staging, "repository", "src", "contrib")
  dir.create(repository, recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(source_cache, archives), repository, overwrite = FALSE)

  build_dir <- tempfile("dcc-build-")
  dir.create(build_dir)
  on.exit(unlink(build_dir, recursive = TRUE), add = TRUE)
  old <- setwd(build_dir)
  on.exit(setwd(old), add = TRUE)
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "build", "--no-manual", "--no-build-vignettes", shQuote(root)),
    stdout = file.path(build_dir, "build.log"),
    stderr = file.path(build_dir, "build.log")
  )
  setwd(old)
  if (!identical(status, 0L)) stop("R CMD build failed; see build log.")
  dcc_tarball <- list.files(
    build_dir, pattern = "^DCC_.*[.]tar[.]gz$", full.names = TRUE
  )
  if (length(dcc_tarball) != 1L) stop("Expected one DCC source tarball.")
  file.copy(dcc_tarball, repository, overwrite = FALSE)
  tools::write_PACKAGES(repository, type = "source")
  file.copy(file.path(root, "renv.lock"), staging)
  file.copy(file.path(root, "docs", "installation.md"), staging)
  write_install_script(file.path(staging, "install-DCC.R"))
  write_license_inventory(
    root, names(lock$Packages), file.path(staging, "license-inventory.csv")
  )
  write_report(file.path(staging, "verification-report.json"), list(
    contract_version = "1.0", status = "complete",
    contains_user_data = FALSE, package = "DCC", version = version,
    dependency_source_archives = length(archives),
    repository_index = "repository/src/contrib/PACKAGES",
    lockfile = "renv.lock", install_script = "install-DCC.R"
  ))
  writeLines(c(
    paste("DCC", version, "internal offline source bundle"),
    "This bundle contains package source archives, metadata, and no user data.",
    "Verify SHA256SUMS, then run: Rscript install-DCC.R /path/to/library"
  ), file.path(staging, "README.txt"), useBytes = TRUE)
  write_checksums(staging)
  if (!file.rename(staging, output)) stop("Could not finalize bundle atomically.")
  cat("INTERNAL BUNDLE: COMPLETE\n", normalizePath(output), "\n")
}

if (sys.nframe() == 0L) main()
