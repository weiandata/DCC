#' Apply a declarative codebook to a dataset
#'
#' Applies a codebook to a [dcc_data()] object or data.frame: per
#' variable it can rename, recode values, declare missing codes, coerce
#' type, attach a variable label, value labels, and a role
#' (`id`/`group`/`weight`/`item`). The preview (`dry_run = TRUE`,
#' default) describes every change it would make and changes nothing;
#' `dry_run = FALSE` returns a new [dcc_data()] version with a
#' `codebook` provenance record. The raw input is never overwritten.
#'
#' The codebook is a named list keyed by (current) variable name. Each
#' entry is a list with any of: `rename` (new name), `recode` (a named
#' old -> new value map), `missing` (values set to `NA`), `type`
#' (target class, e.g. `"integer"`), `label`, `value_labels` (a named
#' vector), and `role`.
#'
#' The preview and the apply share one internal planner, so a change is
#' previewed exactly as it will be applied. Unknown variables and
#' impossible type coercions raise `dcc_codebook_error`.
#'
#' @param x A `dcc_data` object or data.frame.
#' @param codebook A named list keyed by variable (see Details).
#' @param dry_run If `TRUE` (default), return a
#'   `dcc_codebook_preview`; if `FALSE`, apply and return a new
#'   `dcc_data`.
#' @return A `dcc_codebook_preview` (dry run) or a new `dcc_data`.
#' @examples
#' df <- data.frame(sid = c("S1", "S2"), age = c(25, -99),
#'                  sex = c("1", "2"), stringsAsFactors = FALSE)
#' cb <- list(
#'   age = list(missing = -99, type = "integer"),
#'   sex = list(rename = "gender", recode = c("1" = "M", "2" = "F"),
#'              label = "Gender")
#' )
#' dcc_apply_codebook(df, cb)                 # preview
#' dcc_apply_codebook(df, cb, dry_run = FALSE)  # apply
#' @export
dcc_apply_codebook <- function(x, codebook, dry_run = TRUE) {
  if (!is.list(codebook) || (length(codebook) &&
      (is.null(names(codebook)) || any(!nzchar(names(codebook)))))) {
    dcc_abort("`codebook` must be a named list keyed by variable name.",
              class = "dcc_codebook_error")
  }
  base <- if (inherits(x, "dcc_data")) {
    x
  } else {
    dcc_data(data.table::as.data.table(x))
  }
  dt <- data.table::copy(base$data)

  plan <- list()
  addp <- function(variable, op, detail) {
    plan[[length(plan) + 1L]] <<- data.table::data.table(
      variable = variable, op = op, detail = detail)
  }

  for (nm in names(codebook)) {
    spec <- codebook[[nm]]
    if (!nm %in% names(dt)) {
      dcc_abort("Codebook variable '", nm, "' not found in the data.",
                class = "dcc_codebook_error")
    }
    col <- dt[[nm]]

    if (!is.null(spec$missing)) {
      hit <- as.character(col) %in% as.character(spec$missing)
      addp(nm, "missing", paste0(sum(hit), " value(s) set to NA"))
      if (!dry_run) col[hit] <- NA
    }
    if (!is.null(spec$recode)) {
      map <- spec$recode
      if (is.null(names(map)) || any(!nzchar(names(map)))) {
        dcc_abort("Codebook variable '", nm, "': `recode` must be a named ",
                  "old -> new map.", class = "dcc_codebook_error")
      }
      key <- as.character(col)
      hit <- key %in% names(map)
      addp(nm, "recode", paste0(sum(hit), " value(s) recoded"))
      if (!dry_run && any(hit)) {
        new_raw <- as.character(unname(map[key[hit]]))
        col[hit] <- methods::as(new_raw, class(col)[1L])
      }
    }
    if (!is.null(spec$type)) {
      addp(nm, "type", paste0("coerce to ", spec$type))
      if (!dry_run) {
        col <- tryCatch(
          methods::as(col, spec$type),
          error = function(e) {
            dcc_abort("Codebook variable '", nm, "': cannot coerce to ",
                      spec$type, ".", class = "dcc_codebook_error")
          }
        )
      }
    }
    if (!is.null(spec$label)) {
      addp(nm, "label", as.character(spec$label))
      if (!dry_run) attr(col, "label") <- spec$label
    }
    if (!is.null(spec$value_labels)) {
      addp(nm, "value_labels",
           paste(names(spec$value_labels), collapse = ", "))
      if (!dry_run) attr(col, "labels") <- spec$value_labels
    }
    if (!is.null(spec$role)) {
      addp(nm, "role", as.character(spec$role))
      if (!dry_run) attr(col, "dcc_role") <- spec$role
    }
    if (!dry_run) data.table::set(dt, j = nm, value = col)
    if (!is.null(spec$rename)) {
      addp(nm, "rename", paste0("-> ", spec$rename))
      if (!dry_run) data.table::setnames(dt, nm, as.character(spec$rename))
    }
  }

  changes <- if (length(plan)) {
    data.table::rbindlist(plan)
  } else {
    data.table::data.table(variable = character(), op = character(),
                           detail = character())
  }

  if (dry_run) {
    return(structure(list(changes = changes), class = "dcc_codebook_preview"))
  }
  dcc_data(
    dt,
    meta = base$meta,
    read_report = base$read_report,
    provenance = c(base$provenance, list(new_provenance_record(
      stage = "codebook",
      details = list(n_changes = nrow(changes))
    )))
  )
}

#' The planned changes of a codebook preview
#'
#' @param x A `dcc_codebook_preview` from [dcc_apply_codebook()].
#' @return A `data.table` of `variable`, `op`, and `detail`.
#' @examples
#' df <- data.frame(sid = "S1", age = -99)
#' prev <- dcc_apply_codebook(df, list(age = list(missing = -99)))
#' dcc_codebook_changes(prev)
#' @export
dcc_codebook_changes <- function(x) {
  if (!inherits(x, "dcc_codebook_preview")) {
    dcc_abort("`x` must be a dcc_codebook_preview from dcc_apply_codebook().",
              class = "dcc_type_error")
  }
  x$changes
}

#' @export
print.dcc_codebook_preview <- function(x, ...) {
  cat(sprintf("<dcc_codebook_preview> %d planned change(s)\n",
              nrow(x$changes)))
  if (nrow(x$changes)) print(x$changes)
  invisible(x)
}
