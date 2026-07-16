validate_zip_member <- function(member) {
  if (!is.character(member) || length(member) != 1L || is.na(member) ||
      !nzchar(member)) {
    dcc_abort("ZIP import requires one explicit member name.",
              class = "dcc_import_error")
  }
  normalized <- gsub("\\\\", "/", member)
  if (grepl("(^/|^[A-Za-z]:|(^|/)\\.\\.(/|$)|/$)", normalized)) {
    dcc_abort("Unsafe ZIP member path.", class = "dcc_import_error")
  }
  normalized
}

path_within_directory <- function(path, directory,
                                  windows = .Platform$OS.type == "windows") {
  normalize_separators <- function(value) {
    value <- gsub("\\\\", "/", value)
    sub("/+$", "", value)
  }
  path <- normalize_separators(path)
  directory <- normalize_separators(directory)
  if (isTRUE(windows)) {
    path <- tolower(path)
    directory <- tolower(directory)
  }
  startsWith(path, paste0(directory, "/"))
}

resolve_compressed_source <- function(path, options = list()) {
  lower <- tolower(path)
  limit <- compression_size_limit(options)
  if (grepl("\\.zip$", lower)) {
    member <- validate_zip_member(options$member %||% "")
    if (!file.exists(path)) {
      dcc_abort("Compressed source not found: ", path,
                class = "dcc_import_error")
    }
    listing <- utils::unzip(path, list = TRUE)
    matches <- which(gsub("\\\\", "/", listing$Name) == member)
    if (length(matches) != 1L) {
      dcc_abort("Declared ZIP member not found exactly once: ", member, ".",
                class = "dcc_import_error")
    }
    if (listing$Length[matches] > limit) {
      dcc_abort("Declared ZIP member exceeds the uncompressed size limit.",
                class = "dcc_import_error")
    }
    target_dir <- tempfile("dcc-unzip-")
    if (!dir.create(target_dir, recursive = FALSE)) {
      dcc_abort("Could not create ZIP extraction directory.",
                class = "dcc_import_error")
    }
    extracted <- tryCatch(
      utils::unzip(path, files = listing$Name[matches], exdir = target_dir,
                   overwrite = FALSE, junkpaths = FALSE),
      error = function(e) {
        unlink(target_dir, recursive = TRUE, force = TRUE)
        dcc_abort("Could not extract declared ZIP member: ",
                  conditionMessage(e), class = "dcc_import_error")
      }
    )
    candidate <- file.path(target_dir, member)
    if (!file.exists(candidate) && length(extracted) == 1L) {
      candidate <- extracted
    }
    root <- normalizePath(target_dir, winslash = "/", mustWork = TRUE)
    resolved <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
    if (!path_within_directory(resolved, root)) {
      unlink(target_dir, recursive = TRUE, force = TRUE)
      dcc_abort("ZIP member escaped the extraction directory.",
                class = "dcc_import_error")
    }
    attr(resolved, "dcc_cleanup_dir") <- target_dir
    return(resolved)
  }

  if (grepl("\\.gz$", lower)) {
    if (!file.exists(path)) {
      dcc_abort("Compressed source not found: ", path,
                class = "dcc_import_error")
    }
    target_dir <- tempfile("dcc-gzip-")
    if (!dir.create(target_dir, recursive = FALSE)) {
      dcc_abort("Could not create gzip extraction directory.",
                class = "dcc_import_error")
    }
    target_name <- sub("\\.gz$", "", basename(path), ignore.case = TRUE)
    target <- file.path(target_dir, target_name)
    input <- gzfile(path, open = "rb")
    output <- file(target, open = "wb")
    ok <- FALSE
    total <- 0
    tryCatch({
      repeat {
        bytes <- readBin(input, what = "raw", n = 1024L * 1024L)
        if (!length(bytes)) break
        total <- total + length(bytes)
        if (total > limit) {
          dcc_abort("Gzip source exceeds the uncompressed size limit.",
                    class = "dcc_import_error")
        }
        writeBin(bytes, output)
      }
      ok <- TRUE
    }, error = function(e) {
      dcc_abort("Could not decompress gzip source: ", conditionMessage(e),
                class = "dcc_import_error")
    }, finally = {
      close(input)
      close(output)
      if (!ok) unlink(target_dir, recursive = TRUE, force = TRUE)
    })
    resolved <- normalizePath(target, mustWork = TRUE)
    attr(resolved, "dcc_cleanup_dir") <- target_dir
    return(resolved)
  }

  if (!file.exists(path)) {
    dcc_abort("Source not found: ", path, class = "dcc_import_error")
  }
  normalizePath(path, mustWork = TRUE)
}

compression_size_limit <- function(options) {
  limit <- options$max_uncompressed_bytes %||% (2 * 1024^3)
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) || limit <= 0) {
    dcc_abort("`max_uncompressed_bytes` must be one positive number.",
              class = "dcc_import_error")
  }
  as.numeric(limit)
}

cleanup_resolved_source <- function(path) {
  cleanup <- attr(path, "dcc_cleanup_dir", exact = TRUE)
  if (!is.null(cleanup) && dir.exists(cleanup)) {
    unlink(cleanup, recursive = TRUE, force = TRUE)
  }
  invisible(NULL)
}
