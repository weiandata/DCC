#' Map multi-form responses onto the master item bank
#'
#' Aligns item columns from multiple test forms onto the master item
#' bank using an external form-item mapping table, producing one column
#' per master item. Items not administered on a respondent's form are
#' structural `NA` -- the concurrent-calibration layout consumed by the
#' downstream IRTC engine (see `docs/design.md`, section 6.2.1). The
#' anchor flag is carried through for fixed-anchor equating.
#'
#' Mapping problems are findings, not silent drops: source columns
#' referenced by the map but absent from the data yield
#' `MAP_SOURCE_MISSING` findings, and respondents whose form is not in
#' the map yield `MAP_UNKNOWN_FORM` findings (their master item cells
#' stay `NA`). The findings table is attached to the result as the
#' `dcc_findings` attribute.
#'
#' @param x A [dcc_data()] object or data.frame of responses.
#' @param form_item_map A data.frame with columns `form` (form id),
#'   `source` (item column on that form), `master` (master item bank
#'   id) and optionally `is_anchor` (logical, default `FALSE`) -- or a
#'   path to a CSV file with those columns (hash recorded in
#'   provenance).
#' @param form_var Name of the column in `x` holding each respondent's
#'   form id.
#' @return A new [dcc_data()] version: non-item columns pass through,
#'   consumed source columns are dropped, and one column per master
#'   item is appended (`NA` where not administered). The normalized
#'   item map (with `is_anchor`) is attached as the `dcc_item_map`
#'   attribute, mapping findings as the `dcc_findings` attribute, and a
#'   `map_forms` provenance record is appended.
#' @export
dcc_map_forms <- function(x, form_item_map, form_var) {
  map_hash <- NA_character_
  map_source <- NA_character_
  if (is.character(form_item_map) && length(form_item_map) == 1L) {
    if (!file.exists(form_item_map)) {
      dcc_abort("Form-item map file not found: ", form_item_map,
                class = "dcc_io_error")
    }
    map_source <- normalizePath(form_item_map)
    map_hash <- unname(tools::md5sum(form_item_map))
    form_item_map <- data.table::fread(form_item_map)
  }
  map <- normalize_item_map(form_item_map)

  dt <- if (inherits(x, "dcc_data")) {
    data.table::copy(x$data)
  } else {
    data.table::as.data.table(x)
  }
  if (!form_var %in% names(dt)) {
    dcc_abort("`form_var` '", form_var, "' not found in data.",
              class = "dcc_type_error")
  }
  forms <- as.character(dt[[form_var]])

  findings <- list()

  # Source columns referenced by the map but missing from the data.
  missing_src <- map[!map$source %in% names(dt), ]
  if (nrow(missing_src)) {
    findings[[length(findings) + 1L]] <- dcc_findings(
      record_id = NA_character_,
      variable = missing_src$source,
      check_id = "MAP_SOURCE_MISSING",
      evidence = sprintf(
        "form '%s': source column '%s' (master '%s') not present in data",
        missing_src$form, missing_src$source, missing_src$master
      ),
      severity = "fail",
      dimension = "completeness"
    )
    map <- map[map$source %in% names(dt), ]
  }

  # Respondents on forms the map does not know.
  unknown <- which(!forms %in% unique(map$form))
  if (length(unknown)) {
    findings[[length(findings) + 1L]] <- dcc_findings(
      record_id = as.character(unknown),
      variable = form_var,
      check_id = "MAP_UNKNOWN_FORM",
      evidence = sprintf("form '%s' not present in the form-item map",
                         forms[unknown]),
      severity = "fail",
      dimension = "validity"
    )
  }

  masters <- unique(map$master)
  out <- data.table::copy(dt)
  consumed <- intersect(unique(map$source), names(out))
  if (length(consumed)) {
    out[, (consumed) := NULL]
  }

  for (m_id in masters) {
    sub <- map[map$master == m_id, ]
    col <- rep(NA_character_, nrow(dt))
    for (j in seq_len(nrow(sub))) {
      rows <- which(forms == sub$form[j])
      if (length(rows)) {
        col[rows] <- as.character(dt[[sub$source[j]]][rows])
      }
    }
    data.table::set(out, j = m_id, value = col)
  }

  found <- bind_findings(findings)
  base <- if (inherits(x, "dcc_data")) x else dcc_data(dt)
  result <- dcc_data(
    out,
    meta = base$meta,
    read_report = base$read_report,
    provenance = c(base$provenance, list(new_provenance_record(
      stage = "map_forms",
      details = list(
        map_source = map_source,
        map_hash = map_hash,
        n_masters = length(masters),
        n_anchors = length(unique(map$master[map$is_anchor])),
        n_findings = nrow(found)
      ),
      hashes = list(form_map = map_hash),
      counts = list(masters = length(masters),
                    anchors = length(unique(map$master[map$is_anchor])),
                    findings = nrow(found), rows = nrow(out))
    )))
  )
  data.table::setattr(result, "dcc_item_map", map)
  data.table::setattr(result, "dcc_findings", found)
  result
}

normalize_item_map <- function(form_item_map) {
  if (!is.data.frame(form_item_map)) {
    dcc_abort("`form_item_map` must be a data.frame or a CSV path.",
              class = "dcc_type_error")
  }
  map <- data.table::as.data.table(form_item_map)
  need <- c("form", "source", "master")
  if (!all(need %in% names(map))) {
    dcc_abort("Form-item map needs columns: ",
              paste(need, collapse = ", "), ".",
              class = "dcc_map_error")
  }
  if (!"is_anchor" %in% names(map)) map[, is_anchor := FALSE]
  map[, form := as.character(form)]
  map[, source := as.character(source)]
  map[, master := as.character(master)]
  map[, is_anchor := as.logical(is_anchor)]
  dup <- map[duplicated(map[, c("form", "master")]), ]
  if (nrow(dup)) {
    dcc_abort("Form-item map has duplicate (form, master) pair(s): ",
              paste(unique(paste(dup$form, dup$master, sep = "/")),
                    collapse = ", "),
              class = "dcc_map_error")
  }
  # An anchor must be flagged consistently across forms.
  flags <- map[, list(n = length(unique(is_anchor))), by = "master"]
  if (any(flags$n > 1L)) {
    dcc_abort("Inconsistent is_anchor flag for master item(s): ",
              paste(flags$master[flags$n > 1L], collapse = ", "),
              class = "dcc_map_error")
  }
  map[]
}
