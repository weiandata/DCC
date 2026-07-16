#!/usr/bin/env Rscript

format_dependencies <- function() {
  c(
    "arrow", "data.table", "haven", "jsonlite", "openxlsx2", "readODS",
    "readxl", "stringi", "writexl", "yaml"
  )
}

description_packages <- function(description, field) {
  if (!field %in% colnames(description) || is.na(description[1L, field])) {
    return(character())
  }
  values <- trimws(strsplit(description[1L, field], ",")[[1L]])
  sub("[[:space:]]*\\(.*$", "", values)
}

runtime_calls <- function(path) {
  installer_names <- c(
    "install.packages", "pkg_install", "install_github", "install_version",
    "renv_install"
  )
  parsed <- parse(path, keep.source = TRUE)
  tokens <- utils::getParseData(parsed)
  namespace <- unique(tokens$text[tokens$token == "SYMBOL_PACKAGE"])
  calls <- unique(tokens$text[tokens$token == "SYMBOL_FUNCTION_CALL"])
  list(
    namespace = namespace[nzchar(namespace)],
    installers = intersect(calls, installer_names)
  )
}

dependency_closure <- function(imports) {
  installed <- installed.packages()
  absent <- setdiff(imports, rownames(installed))
  if (length(absent)) {
    stop("Installed library is missing import(s): ", paste(absent, collapse = ", "))
  }
  dependencies <- tools::package_dependencies(
    imports, db = installed, which = c("Depends", "Imports", "LinkingTo"),
    recursive = TRUE
  )
  packages <- unique(c(imports, unlist(dependencies, use.names = FALSE)))
  packages <- intersect(packages, rownames(installed))
  priority <- installed[packages, "Priority"]
  sort(packages[is.na(priority) | !nzchar(priority)])
}

write_dependency_lock <- function(root, path = file.path(root, "renv.lock")) {
  description <- read.dcf(file.path(root, "DESCRIPTION"))
  imports <- description_packages(description, "Imports")
  packages <- dependency_closure(imports)
  installed <- installed.packages(fields = c(
    "Repository", "Depends", "Imports", "LinkingTo"
  ))
  records <- lapply(packages, function(package) {
    fields <- installed[package, ]
    requirements <- unique(unlist(lapply(
      c("Depends", "Imports", "LinkingTo"),
      function(field) {
        value <- fields[[field]]
        if (is.na(value) || !nzchar(value)) return(character())
        names <- trimws(strsplit(value, ",")[[1L]])
        sub("[[:space:]]*\\(.*$", "", names)
      }
    )))
    requirements <- intersect(requirements, packages)
    list(
      Package = package,
      Version = unname(fields[["Version"]]),
      Source = "Repository",
      Repository = if (!is.na(fields[["Repository"]]) &&
                       nzchar(fields[["Repository"]])) {
        unname(fields[["Repository"]])
      } else "CRAN",
      Requirements = as.list(sort(requirements))
    )
  })
  names(records) <- packages
  lock <- list(
    R = list(
      Version = paste(R.version$major, R.version$minor, sep = "."),
      Repositories = list(list(
        Name = "CRAN", URL = "https://cloud.r-project.org"
      ))
    ),
    Packages = records
  )
  jsonlite::write_json(
    lock, path, auto_unbox = TRUE, null = "null", na = "null",
    pretty = TRUE
  )
  normalizePath(path, mustWork = TRUE)
}

audit_dependencies <- function(root = getwd()) {
  root <- normalizePath(root, mustWork = TRUE)
  description <- read.dcf(file.path(root, "DESCRIPTION"))
  imports <- description_packages(description, "Imports")
  depends <- setdiff(description_packages(description, "Depends"), "R")
  r_files <- list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)
  calls <- lapply(r_files, runtime_calls)
  namespace_packages <- sort(unique(unlist(lapply(calls, `[[`, "namespace"))))
  install_calls <- sort(unique(unlist(lapply(calls, `[[`, "installers"))))
  undeclared <- setdiff(namespace_packages, c(imports, depends, "base"))
  missing_formats <- setdiff(format_dependencies(), imports)
  closure <- dependency_closure(imports)
  lock_path <- file.path(root, "renv.lock")
  locked <- character()
  mismatches <- character()
  if (file.exists(lock_path)) {
    lock <- jsonlite::read_json(lock_path, simplifyVector = FALSE)
    locked <- names(lock$Packages)
    installed <- installed.packages()
    # Direct Imports must match the active build library exactly. Transitive
    # records may deliberately use a newer repository source version when the
    # active binary has a platform-only revision that cannot be bundled.
    common <- intersect(imports, locked)
    mismatches <- common[vapply(common, function(package) {
      !identical(
        as.character(lock$Packages[[package]]$Version),
        as.character(installed[package, "Version"])
      )
    }, logical(1))]
  }
  ok <- !length(undeclared) && !length(install_calls) &&
    !length(missing_formats) && all(closure %in% locked) && !length(mismatches)
  list(
    ok = ok, imports = imports, format_dependencies = format_dependencies(),
    undeclared_namespace_calls = undeclared,
    runtime_install_calls = install_calls,
    missing_format_dependencies = missing_formats,
    locked_packages = closure,
    lock_missing_packages = setdiff(closure, locked),
    lock_version_mismatches = mismatches
  )
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  root <- normalizePath(getwd(), mustWork = TRUE)
  if ("--write-lock" %in% args) {
    cat("Wrote", write_dependency_lock(root), "\n")
  }
  audit <- audit_dependencies(root)
  if (!audit$ok) {
    print(audit[c(
      "undeclared_namespace_calls", "runtime_install_calls",
      "missing_format_dependencies", "lock_missing_packages",
      "lock_version_mismatches"
    )])
    cat("DEPENDENCIES: FAIL\n")
    quit(status = 1L)
  }
  cat(sprintf(
    "DEPENDENCIES: PASS (%d imports; %d locked packages)\n",
    length(audit$imports), length(audit$locked_packages)
  ))
}

if (sys.nframe() == 0L) main()
