#' Read an Excel cleaning-plan configuration
#'
#' Converts an Excel cleaning-plan workbook into a [dcc_config()], so
#' survey staff specify the record ID, item columns, rules, and
#' dispositions in a spreadsheet rather than writing YAML.
#'
#' The workbook has two sheets. `settings` has `key`/`value` rows
#' (`id_var`, optional `items` as a comma-separated list). `rules` has
#' one row per check with columns `id`, `type`, `variable`, `min`,
#' `max`, `values` (comma-separated), `items` (comma-separated),
#' `max_prop`, `max_run`, `time_var`, `min_seconds`, `traps`
#' (`var=expected` pairs), `severity`, `action`, and `recode_map`
#' (`old=new` pairs). Write a starter workbook with
#' [dcc_write_config_template()].
#'
#' @param path Path to the `.xlsx` cleaning-plan workbook.
#' @return A `dcc_config`.
#' @seealso [dcc_write_config_template()], [dcc_config()], [dcc_run()].
#' @export
dcc_read_config <- function(path) {
  if (!file.exists(path)) {
    dcc_abort("Config file not found: ", path, class = "dcc_io_error")
  }
  sheets <- readxl::excel_sheets(path)
  if (!all(c("settings", "rules") %in% sheets)) {
    dcc_abort("Config workbook needs `settings` and `rules` sheets; found: ",
              paste(sheets, collapse = ", "), ".", class = "dcc_config_error")
  }
  settings <- as.data.frame(readxl::read_excel(path, sheet = "settings"))
  rules_df <- as.data.frame(readxl::read_excel(path, sheet = "rules"))

  id_var <- cfg_setting(settings, "id_var")
  items_raw <- cfg_setting(settings, "items")
  items <- if (!is.na(items_raw) && nzchar(items_raw)) {
    trimws(strsplit(items_raw, ",")[[1]])
  } else {
    NULL
  }

  checks <- list()
  actions <- list()
  for (i in seq_len(nrow(rules_df))) {
    row <- rules_df[i, , drop = FALSE]
    id <- cfg_chr(row, "id")
    type <- cfg_chr(row, "type")
    if (is.na(id) || !nzchar(id)) {
      dcc_abort("Config `rules` row ", i, " has no `id`.",
                class = "dcc_config_error")
    }
    if (is.na(type) || !nzchar(type)) {
      dcc_abort("Config rule '", id, "' has no `type`.",
                class = "dcc_config_error")
    }
    ch <- list(id = id, type = type)
    variable <- cfg_chr(row, "variable")
    if (!is.na(variable)) ch$variable <- variable
    mn <- cfg_num(row, "min")
    if (!is.na(mn)) ch$min <- mn
    mx <- cfg_num(row, "max")
    if (!is.na(mx)) ch$max <- mx
    vals <- cfg_chr(row, "values")
    if (!is.na(vals) && nzchar(vals)) {
      ch$values <- trimws(strsplit(vals, ",")[[1]])
    }
    its <- cfg_chr(row, "items")
    if (!is.na(its) && nzchar(its)) {
      ch$items <- trimws(strsplit(its, ",")[[1]])
    }
    mp <- cfg_num(row, "max_prop")
    if (!is.na(mp)) ch$max_prop <- mp
    mr <- cfg_num(row, "max_run")
    if (!is.na(mr)) ch$max_run <- as.integer(mr)
    tv <- cfg_chr(row, "time_var")
    if (!is.na(tv)) ch$time_var <- tv
    ms <- cfg_num(row, "min_seconds")
    if (!is.na(ms)) ch$min_seconds <- ms
    tr <- cfg_chr(row, "traps")
    if (!is.na(tr) && nzchar(tr)) ch$traps <- cfg_parse_pairs(tr)
    sev <- cfg_chr(row, "severity")
    if (!is.na(sev) && nzchar(sev)) ch$severity <- sev
    checks[[length(checks) + 1L]] <- ch

    act <- cfg_chr(row, "action")
    if (!is.na(act) && nzchar(act)) {
      key <- cfg_produced_id(type, id)
      if (identical(act, "recode")) {
        rm_raw <- cfg_chr(row, "recode_map")
        if (is.na(rm_raw) || !nzchar(rm_raw)) {
          dcc_abort("Config rule '", id, "' has a recode action but no ",
                    "`recode_map`.", class = "dcc_config_error")
        }
        actions[[key]] <- list(action = "recode",
                               map = cfg_parse_map(rm_raw))
      } else {
        actions[[key]] <- act
      }
    }
  }

  ruleset <- structure(
    list(checks = checks, source = normalizePath(path),
         hash = unname(tools::md5sum(path))),
    class = "dcc_ruleset"
  )
  dcc_config(ruleset, actions = actions,
             id_var = if (is.na(id_var)) NULL else id_var, items = items)
}

#' Write a starter Excel cleaning-plan template
#'
#' Writes an example two-sheet cleaning-plan workbook that
#' [dcc_read_config()] can read, for survey staff to edit.
#'
#' @param path Output `.xlsx` path.
#' @return `path`, invisibly.
#' @seealso [dcc_read_config()].
#' @export
dcc_write_config_template <- function(path) {
  dcc_require("writexl", "write an Excel cleaning-plan template")
  settings <- data.frame(
    key = c("id_var", "items"),
    value = c("sid", "q1,q2,q3"),
    stringsAsFactors = FALSE
  )
  rules <- data.frame(
    id = c("R001", "M001"),
    type = c("range", "missing_items"),
    variable = c("score", NA),
    min = c(0, NA),
    max = c(100, NA),
    values = c(NA, NA),
    items = c(NA, "q1,q2,q3"),
    max_prop = c(NA, 0.5),
    max_run = c(NA, NA),
    time_var = c(NA, NA),
    min_seconds = c(NA, NA),
    traps = c(NA, NA),
    severity = c("fail", NA),
    action = c("set_na", "flag"),
    recode_map = c(NA, NA),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(list(settings = settings, rules = rules), path)
  invisible(path)
}

# --- workbook parsing helpers ----------------------------------------

cfg_setting <- function(settings, key) {
  if (!all(c("key", "value") %in% names(settings))) {
    return(NA_character_)
  }
  hit <- which(as.character(settings$key) == key)
  if (!length(hit)) {
    return(NA_character_)
  }
  v <- settings$value[hit[1L]]
  if (is.na(v)) NA_character_ else trimws(as.character(v))
}

cfg_chr <- function(row, nm) {
  if (!nm %in% names(row)) {
    return(NA_character_)
  }
  v <- row[[nm]][1L]
  if (is.na(v)) NA_character_ else trimws(as.character(v))
}

cfg_num <- function(row, nm) {
  if (!nm %in% names(row)) {
    return(NA_real_)
  }
  v <- row[[nm]][1L]
  if (is.na(v)) NA_real_ else suppressWarnings(as.numeric(v))
}

# Parse "a=1, b=2" into a named list, numeric where possible.
cfg_parse_pairs <- function(s) {
  parts <- trimws(strsplit(s, ",")[[1]])
  kv <- strsplit(parts, "=")
  out <- lapply(kv, function(p) {
    n <- suppressWarnings(as.numeric(p[2L]))
    if (is.na(n)) trimws(p[2L]) else n
  })
  names(out) <- vapply(kv, function(p) trimws(p[1L]), character(1))
  out
}

# Parse "old=new, old2=new2" into a named character vector.
cfg_parse_map <- function(s) {
  parts <- trimws(strsplit(s, ",")[[1]])
  kv <- strsplit(parts, "=")
  out <- vapply(kv, function(p) trimws(p[2L]), character(1))
  names(out) <- vapply(kv, function(p) trimws(p[1L]), character(1))
  out
}

# Every workbook action is keyed by its declared rule id.
cfg_produced_id <- function(type, id) {
  id
}
