#' Run record-local checks over a file in chunks
#'
#' Larger-than-memory detection for delimited files: the file is read
#' in chunks of `chunk_size` rows and every check is evaluated per
#' chunk, so peak memory stays bounded by the chunk, not the file. The
#' combined findings are identical to what [dcc_detect()] would return
#' in memory -- guaranteed only for *record-local* checks, which is why
#' cross-record checks are rejected up front with a typed error:
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
#' @param path Path to a delimited text file (CSV/TSV). The encoding
#'   must be fread-native (`UTF-8` or `latin1`); convert other
#'   encodings once via [dcc_read()] + export before chunked runs.
#' @param rules A `dcc_ruleset` from [dcc_rules()].
#' @param chunk_size Rows per chunk (default 100000).
#' @param id_var Name of the record-id column, or `NULL` to use global
#'   row numbers (consistent across chunks).
#' @param sep Field separator (default `","`).
#' @return A [dcc_findings()] table with `n_rows` (total rows scanned)
#'   and `n_chunks` attributes.
#' @export
dcc_detect_chunked <- function(path, rules, chunk_size = 100000L,
                               id_var = NULL, sep = ",") {
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
  enc <- dcc_detect_encoding(path)
  if (!enc$encoding %in% c("UTF-8", "latin1")) {
    dcc_abort("Chunked detection needs an fread-native encoding ",
              "(UTF-8/latin1); detected ", enc$encoding,
              ". Convert once via dcc_read() and re-export first.",
              class = "dcc_encoding_error")
  }
  fread_enc <- if (enc$encoding == "latin1") "Latin-1" else "UTF-8"

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
    if (is.null(id_var)) {
      # Global row numbers must be consistent across chunks.
      data.table::set(dt, j = ".dcc_row_id",
                      value = as.character(offset + seq_len(nrow(dt))))
      eff_id <- ".dcc_row_id"
    } else {
      eff_id <- id_var
    }
    findings[[length(findings) + 1L]] <- bind_findings(
      lapply(rules$checks, function(ch) eval_check(dt, ch, id_var = eff_id))
    )
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
