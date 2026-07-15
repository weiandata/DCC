#' Score responses against an answer key
#'
#' Scores cleaned responses using an external, versioned answer key and
#' appends one `<item>_score` column per keyed item plus a
#' `total_score` column, as a new dataset version. Supported item
#' types:
#'
#' * `single` -- full points when the response equals the key.
#' * `multiple` -- multi-select items; the response and key are strings
#'   of selected options (e.g. `"AC"`, or `"A,C"`). With
#'   `partial = FALSE` (default) all-or-nothing; with `partial = TRUE`
#'   the score is `points * max(0, (hits - false_alarms) / n_key)`.
#'
#' A pluggable `scoring_fn` overrides the built-in scoring: it receives
#' the response vector and the key row (list) and must return a numeric
#' vector with exactly one value per response, which reserves room for
#' weighted/rubric/polytomous scoring without API changes (design decision 2).
#'
#' Omitted responses (`NA`) are scored per `omit_policy`: `"zero"`
#' (default) or `"na"`. Structural missingness from multi-form designs
#' should stay `NA`: run [dcc_map_forms()] first and score with
#' `omit_policy = "na"` for not-administered items, or score per form.
#'
#' @param x A [dcc_data()] object or data.frame of responses.
#' @param answer_key A data.frame with columns `item`, `key`, and
#'   optionally `type` (`"single"`/`"multiple"`, default `"single"`),
#'   `points` (default 1), `partial` (default `FALSE`) -- or a path to
#'   a CSV file with those columns (the file's MD5 hash is recorded in
#'   the provenance chain).
#' @param omit_policy `"zero"` (omitted item scores 0) or `"na"`.
#' @param scoring_fn Optional `function(responses, key_row)` returning
#'   a numeric vector; replaces built-in scoring for every item.
#' @return A new [dcc_data()] version with `<item>_score` columns and
#'   `total_score` appended, and a `score` provenance record (key
#'   source, key hash, omit policy).
#' @export
dcc_score <- function(x, answer_key, omit_policy = c("zero", "na"),
                      scoring_fn = NULL) {
  omit_policy <- match.arg(omit_policy)
  key_hash <- NA_character_
  key_source <- NA_character_
  if (is.character(answer_key) && length(answer_key) == 1L) {
    if (!file.exists(answer_key)) {
      dcc_abort("Answer key file not found: ", answer_key,
                class = "dcc_io_error")
    }
    key_source <- normalizePath(answer_key)
    key_hash <- unname(tools::md5sum(answer_key))
    answer_key <- data.table::fread(answer_key)
  }
  key <- normalize_answer_key(answer_key)

  dt <- if (inherits(x, "dcc_data")) {
    data.table::copy(x$data)
  } else {
    data.table::as.data.table(x)
  }
  missing_items <- setdiff(key$item, names(dt))
  if (length(missing_items)) {
    dcc_abort("Answer key item(s) not in data: ",
              paste(missing_items, collapse = ", "),
              class = "dcc_score_error")
  }

  score_cols <- character(nrow(key))
  for (i in seq_len(nrow(key))) {
    krow <- as.list(key[i, ])
    resp <- dt[[krow$item]]
    s <- if (!is.null(scoring_fn)) {
      raw_score <- scoring_fn(resp, krow)
      if (!is.numeric(raw_score) || length(raw_score) != length(resp)) {
        dcc_abort("`scoring_fn` must return a numeric vector of length ",
                  length(resp), ".", class = "dcc_score_error")
      }
      as.numeric(raw_score)
    } else if (krow$type == "single") {
      score_single(resp, krow)
    } else {
      score_multiple(resp, krow)
    }
    if (omit_policy == "zero") {
      s[is.na(resp)] <- 0
    } else {
      s[is.na(resp)] <- NA_real_
    }
    col <- paste0(krow$item, "_score")
    score_cols[i] <- col
    data.table::set(dt, j = col, value = s)
  }
  score_dt <- dt[, score_cols, with = FALSE]
  total <- rowSums(score_dt, na.rm = TRUE)
  if (omit_policy == "na") {
    total[rowSums(!is.na(score_dt)) == 0L] <- NA_real_
  }
  data.table::set(dt, j = "total_score", value = total)

  base <- if (inherits(x, "dcc_data")) x else dcc_data(dt)
  dcc_data(
    dt,
    meta = base$meta,
    read_report = base$read_report,
    dictionary = base$dictionary,
    missing_states = base$missing_states,
    import_spec = base$import_spec,
    provenance = c(base$provenance, list(new_provenance_record(
      stage = "score",
      details = list(
        n_items = nrow(key),
        key_source = key_source,
        keyfile_hash = key_hash,
        omit_policy = omit_policy,
        custom_scoring = !is.null(scoring_fn)
      ),
      hashes = list(keyfile = key_hash),
      counts = list(items = nrow(key), rows = nrow(dt))
    )))
  )
}

normalize_answer_key <- function(answer_key) {
  if (!is.data.frame(answer_key)) {
    dcc_abort("`answer_key` must be a data.frame or a CSV path.",
              class = "dcc_type_error")
  }
  key <- data.table::as.data.table(answer_key)
  if (!all(c("item", "key") %in% names(key))) {
    dcc_abort("Answer key needs `item` and `key` columns.",
              class = "dcc_score_error")
  }
  if (!"type" %in% names(key)) key[, type := "single"]
  if (!"points" %in% names(key)) key[, points := 1]
  if (!"partial" %in% names(key)) key[, partial := FALSE]
  key[, type := tolower(as.character(type))]
  bad_type <- setdiff(unique(key$type), c("single", "multiple"))
  if (length(bad_type)) {
    dcc_abort("Unknown answer key type(s): ",
              paste(bad_type, collapse = ", "),
              class = "dcc_score_error")
  }
  if (anyDuplicated(key$item)) {
    dcc_abort("Duplicate item(s) in answer key.", class = "dcc_score_error")
  }
  key[]
}

score_single <- function(resp, krow) {
  as.numeric(as.character(resp) == as.character(krow$key)) * krow$points
}

# Split a multi-select string like "AC" or "A,C" or "A C" into options.
split_options <- function(s) {
  parts <- strsplit(as.character(s), "[,;[:space:]]+")
  lapply(parts, function(p) {
    p <- p[!is.na(p) & nzchar(p)]
    if (length(p) == 1L && nchar(p) > 1L) {
      strsplit(p, "")[[1]]
    } else {
      p
    }
  })
}

score_multiple <- function(resp, krow) {
  key_opts <- split_options(krow$key)[[1]]
  resp_opts <- split_options(resp)
  vapply(seq_along(resp_opts), function(i) {
    if (is.na(resp[i])) {
      return(NA_real_)
    }
    sel <- resp_opts[[i]]
    hits <- length(intersect(sel, key_opts))
    fa <- length(setdiff(sel, key_opts))
    if (isTRUE(as.logical(krow$partial))) {
      krow$points * max(0, (hits - fa) / length(key_opts))
    } else {
      krow$points * as.numeric(hits == length(key_opts) && fa == 0L)
    }
  }, numeric(1))
}
