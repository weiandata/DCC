#' Run record-local checks over a file in chunks
#'
#' Larger-than-memory detection with an adaptive backend: the file is
#' read in chunks (or record batches) of `chunk_size` rows and every
#' check is evaluated per chunk, so peak memory stays bounded by the
#' chunk, not the file. The combined findings are identical to what
#' [dcc_detect()] would return in memory -- guaranteed only for
#' *record-local* checks, which is why cross-record checks are rejected
#' up front with a typed error:
#'
#' * allowed: `range`, `set`, `missing_items`, `straightlining`,
#'   `trap_items`, and `response_time` with an absolute `min_seconds`
#'   cut only (disable the median-relative cut with
#'   `min_median_ratio: ~` in YAML, since a chunk median is not the
#'   file median);
#' * allowed with care: `expr` -- expressions are evaluated per chunk,
#'   so aggregate functions (`mean(x)`, `sum(x)`, ...) see only the
#'   chunk and must not be used;
#' * rejected: `score_anomaly` (group statistics need the whole file;
#'   run it in memory or on a scored aggregate).
#'
#' Two backends share this one entry point and produce identical
#' findings; `backend` selects between them:
#'
#' * `"csv"` -- streams a delimited text file with
#'   [data.table::fread()]. The encoding must be fread-native
#'   (`UTF-8` or `latin1`); convert other encodings once via
#'   [dcc_read()] + export before chunked runs. Column types are
#'   locked from the first chunk so a later all-`NA` column cannot
#'   drift to another type.
#' * `"arrow"` -- streams a Parquet or Feather file as Arrow record
#'   batches (requires the `arrow` package). Types come from the file
#'   schema and are stable across batches, and the columnar format is
#'   always `UTF-8`, so the encoding restriction does not apply.
#' * `"auto"` (default) -- picks `"arrow"` for `.parquet`/`.feather`
#'   files and `"csv"` for `.csv`/`.tsv`/`.txt`; other extensions
#'   raise a typed error asking for an explicit `backend`.
#'
#' @param path Path to the input file: a delimited text file
#'   (CSV/TSV) for the `csv` backend, or a Parquet/Feather file for
#'   the `arrow` backend.
#' @param rules A `dcc_ruleset` from [dcc_rules()].
#' @param chunk_size Rows per chunk / record batch (default 100000).
#' @param id_var Name of the record-id column, or `NULL` to use global
#'   row numbers (consistent across chunks).
#' @param sep Field separator for the `csv` backend (default `","`);
#'   ignored by the `arrow` backend.
#' @param backend One of `"auto"` (default), `"csv"`, or `"arrow"`.
#' @param encoding Encoding of the `csv` backend input: `"auto"`
#'   (default, auto-detected) or an explicit name such as `"UTF-8"` or
#'   `"latin1"`. Pass one explicitly when auto-detection misfires on
#'   pure-ASCII or low-signal data. Ignored by the `arrow` backend.
#' @return A [dcc_findings()] table with `n_rows` (total rows scanned),
#'   `n_chunks`, and `backend` attributes.
#' @export
dcc_detect_chunked <- function(path, rules, chunk_size = 100000L,
                               id_var = NULL, sep = ",",
                               backend = c("auto", "csv", "arrow"),
                               encoding = "auto") {
  if (!file.exists(path)) {
    dcc_abort("File not found: ", path, class = "dcc_io_error")
  }
  if (!inherits(rules, "dcc_ruleset")) {
    dcc_abort("`rules` must be a dcc_ruleset from dcc_rules().",
              class = "dcc_type_error")
  }
  for (ch in rules$checks) {
    assert_chunk_safe(ch)
  }
  backend <- match.arg(backend)
  if (identical(backend, "auto")) {
    backend <- select_stream_backend(path)
  }

  out <- switch(backend,
    csv = stream_detect_csv(path, rules, chunk_size, id_var, sep, encoding),
    arrow = stream_detect_arrow(path, rules, chunk_size, id_var)
  )
  data.table::setattr(out, "backend", backend)
  out
}

# Choose a chunked backend from the file extension.
select_stream_backend <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("parquet", "feather", "arrow")) {
    "arrow"
  } else if (ext %in% c("csv", "tsv", "txt")) {
    "csv"
  } else {
    dcc_abort("Cannot infer a chunked backend from extension '", ext,
              "'; pass backend = \"csv\" or backend = \"arrow\".",
              class = "dcc_type_error")
  }
}

# Evaluate every check on one in-memory chunk. `offset` is the number
# of rows already scanned; when `id_var` is NULL a global row id is
# assigned so record ids stay consistent across chunks.
detect_one_chunk <- function(dt, rules, offset, id_var) {
  if (is.null(id_var)) {
    data.table::set(dt, j = ".dcc_row_id",
                    value = as.character(offset + seq_len(nrow(dt))))
    eff_id <- ".dcc_row_id"
  } else {
    eff_id <- id_var
  }
  bind_findings(
    lapply(rules$checks, function(ch) eval_check(dt, ch, id_var = eff_id))
  )
}

# CSV/TSV backend: stream the file with fread, chunk by chunk.
stream_detect_csv <- function(path, rules, chunk_size, id_var, sep,
                              encoding = "auto") {
  enc <- if (identical(encoding, "auto")) {
    dcc_detect_encoding(path)$encoding
  } else {
    normalize_encoding(encoding)
  }
  if (!enc %in% c("UTF-8", "latin1")) {
    dcc_abort("Chunked detection needs an fread-native encoding ",
              "(UTF-8/latin1); ",
              if (identical(encoding, "auto")) "detected " else "got ",
              enc, ". Pass encoding = \"UTF-8\"/\"latin1\", or convert ",
              "once via dcc_read() and re-export first.",
              class = "dcc_encoding_error")
  }
  fread_enc <- if (enc == "latin1") "Latin-1" else "UTF-8"

  header <- names(data.table::fread(path, sep = sep, nrows = 0L,
                                    encoding = fread_enc))
  if (!is.null(id_var) && !id_var %in% header) {
    dcc_abort("`id_var` '", id_var, "' not found in file header.",
              class = "dcc_type_error")
  }

  findings <- list()
  offset <- 0L
  n_chunks <- 0L
  col_classes <- NULL
  repeat {
    dt <- tryCatch(
      data.table::fread(
        path, sep = sep, header = FALSE, col.names = header,
        skip = offset + 1L, nrows = chunk_size,
        na.strings = c("", "NA"), encoding = fread_enc,
        colClasses = col_classes
      ),
      error = function(e) {
        # skip beyond EOF (file length an exact multiple of chunk_size)
        if (grepl("skip=", conditionMessage(e), fixed = TRUE)) {
          NULL
        } else {
          stop(e)
        }
      }
    )
    if (is.null(dt) || nrow(dt) == 0L) {
      break
    }
    n_chunks <- n_chunks + 1L
    if (is.null(col_classes)) {
      # Lock column types from the first chunk so later chunks (e.g.
      # with an all-NA column) cannot drift to another type.
      col_classes <- vapply(dt, function(col) class(col)[1L],
                            character(1))
    }
    findings[[length(findings) + 1L]] <-
      detect_one_chunk(dt, rules, offset, id_var)
    offset <- offset + nrow(dt)
    if (nrow(dt) < chunk_size) {
      break
    }
  }

  out <- bind_findings(findings)
  data.table::setattr(out, "n_rows", offset)
  data.table::setattr(out, "n_chunks", n_chunks)
  out
}

# Arrow backend: stream a Parquet/Feather file as record batches. Types
# come from the file schema (stable across batches), so no column-class
# locking is needed and the fread encoding restriction does not apply.
stream_detect_arrow <- function(path, rules, chunk_size, id_var) {
  dcc_require("arrow", "run chunked detection on Parquet/Feather files")
  ext <- tolower(tools::file_ext(path))
  fmt <- if (ext %in% c("feather", "arrow")) "arrow" else "parquet"
  ds <- arrow::open_dataset(path, format = fmt)
  schema_names <- names(ds$schema)
  if (!is.null(id_var) && !id_var %in% schema_names) {
    dcc_abort("`id_var` '", id_var, "' not found in file schema.",
              class = "dcc_type_error")
  }
  scanner <- arrow::Scanner$create(ds, batch_size = chunk_size)
  reader <- scanner$ToRecordBatchReader()

  findings <- list()
  offset <- 0L
  n_chunks <- 0L
  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch) || batch$num_rows == 0L) {
      break
    }
    dt <- data.table::as.data.table(as.data.frame(batch))
    n_chunks <- n_chunks + 1L
    findings[[length(findings) + 1L]] <-
      detect_one_chunk(dt, rules, offset, id_var)
    offset <- offset + nrow(dt)
  }

  out <- bind_findings(findings)
  data.table::setattr(out, "n_rows", offset)
  data.table::setattr(out, "n_chunks", n_chunks)
  out
}

assert_chunk_safe <- function(ch) {
  type <- ch$type %||% ""
  if (type == "score_anomaly") {
    dcc_abort("Check '", ch$id, "' (score_anomaly) needs whole-file ",
              "group statistics and cannot run chunked; run ",
              "dcc_detect() in memory instead.",
              class = "dcc_chunk_error")
  }
  if (type == "response_time") {
    mmr_disabled <- "min_median_ratio" %in% names(ch) &&
      is.null(ch$min_median_ratio)
    if (!mmr_disabled) {
      dcc_abort("Check '", ch$id, "' (response_time) uses the ",
                "median-relative cut, which is not chunk-safe. Set ",
                "`min_median_ratio: ~` and use `min_seconds`.",
                class = "dcc_chunk_error")
    }
    if (is.null(ch$min_seconds)) {
      dcc_abort("Check '", ch$id, "' (response_time) needs ",
                "`min_seconds` in chunked mode.",
                class = "dcc_chunk_error")
    }
  }
  invisible(TRUE)
}
