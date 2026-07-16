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

write_encoded_text <- function(path, text, encoding, bom = FALSE) {
  raw <- stringi::stri_conv(
    text, from = "UTF-8", to = encoding, to_raw = TRUE
  )[[1L]]
  if (bom) raw <- c(as.raw(c(0xEF, 0xBB, 0xBF)), raw)
  writeBin(raw, path)
  invisible(path)
}

csv_text <- function(data, separator = ",") {
  rows <- vapply(seq_len(nrow(data)), function(i) {
    values <- vapply(data[i, , drop = FALSE], function(value) {
      if (is.na(value)) "" else as.character(value)
    }, character(1))
    paste(values, collapse = separator)
  }, character(1))
  paste0(paste(c(paste(names(data), collapse = separator), rows),
               collapse = "\n"), "\n")
}

fixture_data <- function(encoding) {
  names <- if (encoding == "BIG5") {
    c("\u53f0\u5317", "\u9ad8\u96c4")
  } else if (encoding == "Shift-JIS") {
    c("\u6771\u4eac", "\u5927\u962a")
  } else if (encoding %in% c("windows-1252", "latin1")) {
    c("M\u00e1laga", "Z\u00fcrich")
  } else {
    c("\u5317\u4eac", "\u4e0a\u6d77")
  }
  data.frame(
    id = c("S001", "S002"), name = names, score = c(1.5, NA_real_),
    stringsAsFactors = FALSE
  )
}

main <- function() {
  root <- find_project_root()
  force <- "--force" %in% commandArgs(trailingOnly = TRUE)
  if (!requireNamespace("DCC", quietly = TRUE)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("Install DCC first, or install pkgload to generate from source.")
    }
    pkgload::load_all(root, quiet = TRUE)
  }
  output_dir <- file.path(root, "tests", "fixtures", "formats", "generated")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write_fixture <- function(path, writer) {
    if (force || !file.exists(path)) writer()
    invisible(path)
  }
  capabilities <- DCC::dcc_capabilities()$formats
  status_for <- function(format) {
    as.character(capabilities$status[match(format, capabilities$format)])
  }
  entries <- list()
  add <- function(path, format, encoding = "native",
                  declared_encoding = encoding, compression = "none",
                  data = NULL, labels = list(), missing_states = 0L,
                  fixture_status = "generated", options = list(),
                  reason = "") {
    relative <- if (nzchar(path)) {
      substring(normalizePath(path, mustWork = TRUE), nchar(root) + 2L)
    } else ""
    entries[[length(entries) + 1L]] <<- list(
      path = gsub("\\\\", "/", relative), format = format,
      compression = compression, encoding = encoding,
      declared_encoding = declared_encoding, locale = "C.UTF-8",
      source_hash = if (is.null(data)) NA_character_ else canonical_matrix_hash(data),
      expected_canonical_hash = if (is.null(data)) NA_character_ else canonical_matrix_hash(data),
      expected_labels = labels,
      expected_missing_states = as.integer(missing_states),
      capability_level = status_for(format), fixture_status = fixture_status,
      options = options,
      file_sha256 = if (nzchar(path)) unname(as.character(tools::sha256sum(path))) else NA_character_,
      reason = reason
    )
  }

  encoding_cases <- list(
    list(name = "UTF-8", iconv = "UTF-8", bom = FALSE),
    list(name = "UTF-8-BOM", iconv = "UTF-8", bom = TRUE),
    list(name = "UTF-16LE", iconv = "UTF-16LE", bom = FALSE),
    list(name = "UTF-16BE", iconv = "UTF-16BE", bom = FALSE),
    list(name = "GB18030", iconv = "GB18030", bom = FALSE),
    list(name = "GBK", iconv = "GBK", bom = FALSE),
    list(name = "BIG5", iconv = "BIG5", bom = FALSE),
    list(name = "Shift-JIS", iconv = "Shift-JIS", bom = FALSE),
    list(name = "windows-1252", iconv = "windows-1252", bom = FALSE),
    list(name = "latin1", iconv = "ISO-8859-1", bom = FALSE)
  )
  for (case in encoding_cases) {
    data <- fixture_data(case$name)
    path <- file.path(output_dir, paste0(
      "responses-", tolower(gsub("[^A-Za-z0-9]+", "-", case$name)), ".csv"
    ))
    write_fixture(path, function() {
      write_encoded_text(path, csv_text(data), case$iconv, case$bom)
    })
    declared <- if (case$name == "UTF-8-BOM") "UTF-8" else case$name
    add(path, "csv", case$name, declared, data = data, missing_states = 1L)
  }

  data <- fixture_data("UTF-8")
  tsv <- file.path(output_dir, "responses-utf8.tsv")
  write_fixture(tsv, function() {
    write_encoded_text(tsv, csv_text(data, "\t"), "UTF-8")
  })
  add(tsv, "tsv", "UTF-8", data = data, missing_states = 1L)
  txt <- file.path(output_dir, "responses-utf8.txt")
  write_fixture(txt, function() {
    write_encoded_text(txt, csv_text(data, ";"), "UTF-8")
  })
  add(txt, "txt", "UTF-8", data = data, missing_states = 1L,
      options = list(delimiter = ";"))

  json <- file.path(output_dir, "responses.json")
  write_fixture(json, function() {
    jsonlite::write_json(data, json, dataframe = "rows", na = "null")
  })
  add(json, "json", "UTF-8", data = data, missing_states = 1L)
  jsonl <- file.path(output_dir, "responses.jsonl")
  write_fixture(jsonl, function() {
    connection <- file(jsonl, open = "wb")
    on.exit(close(connection), add = TRUE)
    jsonlite::stream_out(data, connection, verbose = FALSE, na = "null")
  })
  add(jsonl, "jsonl", "UTF-8", data = data, missing_states = 1L)

  xlsx <- file.path(output_dir, "responses.xlsx")
  write_fixture(xlsx, function() writexl::write_xlsx(data, xlsx))
  add(xlsx, "xlsx", data = data, missing_states = 1L)
  ods <- file.path(output_dir, "responses.ods")
  write_fixture(ods, function() readODS::write_ods(data, ods))
  add(ods, "ods", data = data, missing_states = 1L)
  rds <- file.path(output_dir, "responses.rds")
  write_fixture(rds, function() saveRDS(data, rds, version = 2))
  add(rds, "rds", data = data, missing_states = 1L)

  statistical <- data
  statistical$score <- haven::labelled(statistical$score, label = "Survey score")
  sav <- file.path(output_dir, "responses.sav")
  write_fixture(sav, function() haven::write_sav(statistical, sav))
  add(sav, "spss", data = data, labels = list(score = "Survey score"), missing_states = 1L)
  zsav <- file.path(output_dir, "responses.zsav")
  write_fixture(zsav, function() {
    haven::write_sav(statistical, zsav, compress = "zsav")
  })
  add(zsav, "spss", data = data, labels = list(score = "Survey score"), missing_states = 1L)
  dta <- file.path(output_dir, "responses.dta")
  write_fixture(dta, function() haven::write_dta(statistical, dta))
  add(dta, "stata", data = data, labels = list(score = "Survey score"), missing_states = 1L)
  sas <- file.path(output_dir, "responses.sas7bdat")
  write_fixture(sas, function() {
    suppressWarnings(haven::write_sas(statistical, sas))
  })
  add(sas, "sas", data = data, labels = list(score = "Survey score"), missing_states = 1L)
  xpt <- file.path(output_dir, "responses.xpt")
  write_fixture(xpt, function() haven::write_xpt(statistical, xpt, version = 8))
  add(xpt, "xpt", data = data, labels = list(score = "Survey score"), missing_states = 1L)

  parquet <- file.path(output_dir, "responses.parquet")
  write_fixture(parquet, function() arrow::write_parquet(data, parquet))
  add(parquet, "parquet", data = data, missing_states = 1L)
  feather <- file.path(output_dir, "responses.feather")
  write_fixture(feather, function() arrow::write_feather(data, feather))
  add(feather, "feather", data = data, missing_states = 1L)

  plain_csv <- file.path(output_dir, "responses-compressed.csv")
  write_fixture(plain_csv, function() {
    write_encoded_text(plain_csv, csv_text(data), "UTF-8")
  })
  gzip <- paste0(plain_csv, ".gz")
  write_fixture(gzip, function() {
    input <- file(plain_csv, "rb")
    output <- gzfile(gzip, "wb")
    on.exit(close(input), add = TRUE)
    on.exit(close(output), add = TRUE)
    writeBin(readBin(input, "raw", n = file.size(plain_csv)), output)
  })
  add(gzip, "csv", "UTF-8", compression = "gzip", data = data,
      missing_states = 1L)
  zip <- file.path(output_dir, "responses.zip")
  write_fixture(zip, function() {
    old <- setwd(output_dir)
    on.exit(setwd(old), add = TRUE)
    utils::zip(basename(zip), basename(plain_csv), flags = "-j")
  })
  add(zip, "csv", "UTF-8", compression = "zip", data = data,
      missing_states = 1L,
      options = list(member = basename(plain_csv)))

  external <- list(
    list(format = "xls", encoding = "native", compression = "none",
         reason = "No deterministic legacy XLS writer is a DCC dependency."),
    list(format = "xlsb", encoding = "native", compression = "none",
         reason = "No safe deterministic XLSB writer is available."),
    list(format = "spss", encoding = "POR", compression = "none",
         reason = "POR requires an approved external fixture."),
    list(format = "csv", encoding = "native", compression = "bzip2",
         reason = "The registered compression contract does not support bzip2."),
    list(format = "csv", encoding = "native", compression = "xz",
         reason = "The registered compression contract does not support xz.")
  )
  for (item in external) {
    add("", item$format, item$encoding, compression = item$compression,
        fixture_status = "external_required", reason = item$reason)
  }

  manifest <- list(
    contract_version = "1.0", generator_version = "1.0",
    generated_at = "deterministic-fixture-set",
    package_version = as.character(utils::packageVersion("DCC")),
    fixtures = entries
  )
  path <- file.path(root, "tests", "fixtures", "formats", "manifest.json")
  jsonlite::write_json(manifest, path, auto_unbox = TRUE, dataframe = "rows",
                       na = "null", null = "null", pretty = TRUE, digits = NA)
  action <- if (force) "Regenerated" else "Recorded"
  cat(action, length(entries), "format evidence records at", path, "\n")
}

main()
