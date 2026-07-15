#' Load a declarative rule set from a YAML file
#'
#' Rule files are YAML with embedded R expressions for complex logic
#' (design decision 1 in `docs/design.md`). The top-level key `checks`
#' holds a list of rules; each rule has `id`, `type`, an optional
#' `severity` (`"info"`/`"warn"`/`"fail"`, default `"warn"`),
#' `dimension`, and type-specific fields:
#'
#' * `type: range` -- `variable`, `min` and/or `max`.
#' * `type: set` -- `variable`, `values` (allowed values).
#' * `type: expr` -- `expr`, an R expression evaluated per record in a
#'   restricted environment; records where it evaluates `TRUE` are
#'   flagged.
#' * detector types `missing_items`, `straightlining`, `response_time`,
#'   `trap_items`, `score_anomaly` -- fields are passed to the matching
#'   `detect_*()` function.
#'
#' @param path Path to the YAML rule file.
#' @return A `dcc_ruleset` object (list of normalized rules, with the
#'   source file and its MD5 hash attached for the audit trail).
#' @export
dcc_rules <- function(path) {
  dcc_require("yaml", "read YAML rule files")
  if (!file.exists(path)) {
    dcc_abort("Rule file not found: ", path, class = "dcc_io_error")
  }
  raw <- yaml::read_yaml(path)
  checks <- raw$checks
  if (is.null(checks) || !length(checks)) {
    dcc_abort("Rule file has no `checks` entries: ", path,
              class = "dcc_rule_error")
  }
  ids <- vapply(checks, function(ch) as.character(ch$id %||% ""), "")
  if (any(!nzchar(ids))) {
    dcc_abort("Every check needs an `id`.", class = "dcc_rule_error")
  }
  if (anyDuplicated(ids)) {
    dcc_abort("Duplicate check id(s): ",
              paste(unique(ids[duplicated(ids)]), collapse = ", "),
              class = "dcc_rule_error")
  }
  structure(
    list(
      checks = checks,
      source = normalizePath(path),
      hash = unname(tools::md5sum(path))
    ),
    class = "dcc_ruleset"
  )
}

#' @export
print.dcc_ruleset <- function(x, ...) {
  cat(sprintf("<dcc_ruleset> %d check(s) from %s\n",
              length(x$checks), x$source))
  for (ch in x$checks) {
    cat(sprintf("  - %s [%s] %s\n", ch$id, ch$type %||% "?",
                ch$severity %||% "warn"))
  }
  invisible(x)
}

#' Run a rule set against data (Detect stage)
#'
#' Evaluates every check in a [dcc_rules()] rule set and returns the
#' combined [dcc_findings()] table. Detection is pure and read-only:
#' the same data and the same rule set always produce the same findings,
#' and the input is never modified. When `x` is a [dcc_data()] object, a
#' `detect` record (rule file hash, findings count) is appended to a
#' *copy* of its provenance chain, available via the `dcc_data`
#' attribute of the result.
#'
#' @param x A `dcc_data` object or data.frame.
#' @param rules A `dcc_ruleset` from [dcc_rules()].
#' @param id_var Name of the record-id column, or `NULL` for row
#'   numbers.
#' @return A [dcc_findings()] table. If `x` is a `dcc_data`, the result
#'   carries a `dcc_data` attribute: the input container with a
#'   `detect` provenance record appended.
#' @export
dcc_detect <- function(x, rules, id_var = NULL) {
  if (!inherits(rules, "dcc_ruleset")) {
    dcc_abort("`rules` must be a dcc_ruleset from dcc_rules().",
              class = "dcc_type_error")
  }
  skip_rules <- Filter(
    function(ch) identical(ch$type %||% "", "skip_logic"), rules$checks)
  structural <- build_structural_map(x, skip_rules, id_var)
  results <- lapply(rules$checks, function(ch) {
    if (identical(ch$type %||% "", "skip_logic")) {
      return(empty_findings())
    }
    eval_check(x, ch, id_var = id_var, structural = structural)
  })
  findings <- bind_findings(results)
  resolved <- resolve_data(x, id_var)
  source_hash <- if (inherits(x, "dcc_data") && !is.null(x$meta$file_hash)) {
    x$meta$file_hash
  } else {
    hash_table(resolved$dt)
  }
  run_id <- paste("detect", rules$hash, source_hash, sep = "-")
  if (nrow(findings)) {
    findings[, finding_id := new_finding_ids(
      run_id, check_id, record_id, variable
    )]
  }
  if (inherits(x, "dcc_data")) {
    x2 <- append_provenance(x, "detect", list(
      ruleset = rules$source,
      ruleset_hash = rules$hash,
      n_checks = length(rules$checks),
      n_findings = nrow(findings)
    ))
    data.table::setattr(findings, "dcc_data", x2)
  }
  findings
}

# Build a structural-missingness map from skip_logic rules. Returns a
# logical matrix (data rows x affected variables) where TRUE marks a
# cell that was *not administered* because a skip condition held, or
# NULL when there are no skip_logic rules. Row order matches
# resolve_data(x, id_var), which is what the detectors also use.
build_structural_map <- function(x, skip_rules, id_var = NULL) {
  if (!length(skip_rules)) {
    return(NULL)
  }
  r <- resolve_data(x, id_var)
  dt <- r$dt
  vars <- unique(unlist(lapply(skip_rules,
                               function(ch) unlist(ch$then_not_required))))
  if (!length(vars)) {
    return(NULL)
  }
  m <- matrix(FALSE, nrow = nrow(dt), ncol = length(vars),
              dimnames = list(NULL, vars))
  for (ch in skip_rules) {
    when <- ch$when
    v <- when$variable
    if (is.null(v) || !v %in% names(dt)) {
      dcc_abort("skip_logic check '", ch$id %||% "?",
                "': `when.variable` '", v %||% "<missing>",
                "' not found in the data.", class = "dcc_rule_error")
    }
    if (is.null(when$equals)) {
      dcc_abort("skip_logic check '", ch$id %||% "?",
                "' needs `when.equals`.", class = "dcc_rule_error")
    }
    hit <- !is.na(dt[[v]]) &
      as.character(dt[[v]]) == as.character(when$equals)
    for (nr in unlist(ch$then_not_required)) {
      if (nr %in% colnames(m)) {
        m[hit, nr] <- TRUE
      }
    }
  }
  m
}

# Align a structural map to a specific set of item columns (in `items`
# order), FALSE for items the map does not cover. NULL when there is no
# map or none of the items are covered.
subset_structural <- function(structural, items) {
  if (is.null(structural) || !length(items)) {
    return(NULL)
  }
  present <- intersect(items, colnames(structural))
  if (!length(present)) {
    return(NULL)
  }
  out <- matrix(FALSE, nrow = nrow(structural), ncol = length(items),
                dimnames = list(NULL, items))
  out[, present] <- structural[, present, drop = FALSE]
  out
}

eval_check <- function(x, ch, id_var = NULL, structural = NULL) {
  type <- ch$type %||% ""
  severity <- ch$severity %||% "warn"
  dimension <- ch$dimension %||% NA_character_
  switch(type,
    range = eval_range_check(x, ch, id_var, severity, dimension),
    set = eval_set_check(x, ch, id_var, severity, dimension),
    expr = eval_expr_check(x, ch, id_var, severity, dimension),
    skip_logic = empty_findings(),
    missing_items = detect_missing_items(
      x, items = unlist(ch$items),
      max_prop = ch$max_prop %||% 0.5,
      id_var = id_var, severity = severity,
      structural = subset_structural(structural, unlist(ch$items))
    ),
    straightlining = detect_straightlining(
      x, items = unlist(ch$items),
      max_run = ch$max_run %||% 10L,
      id_var = id_var, severity = severity
    ),
    response_time = detect_response_time(
      x, time_var = ch$time_var,
      min_seconds = ch$min_seconds,
      # An explicitly null key (min_median_ratio: ~) disables the
      # median-relative cut; an absent key keeps the default.
      min_median_ratio = if ("min_median_ratio" %in% names(ch)) {
        ch$min_median_ratio
      } else {
        1 / 3
      },
      id_var = id_var, severity = severity
    ),
    trap_items = detect_trap_items(
      x, traps = ch$traps,
      max_failed = ch$max_failed %||% 1L,
      id_var = id_var, severity = severity
    ),
    score_anomaly = detect_score_anomaly(
      x, score_var = ch$score_var,
      group_vars = if (!is.null(ch$group_vars)) unlist(ch$group_vars),
      method = ch$method %||% "iqr",
      k = ch$k %||% 1.5,
      group_mean_z = ch$group_mean_z %||% 2,
      id_var = id_var, severity = severity
    ),
    dcc_abort("Unknown check type '", type, "' in check '", ch$id, "'.",
              class = "dcc_rule_error")
  )
}

eval_range_check <- function(x, ch, id_var, severity, dimension) {
  r <- resolve_data(x, id_var)
  v <- ch$variable
  if (is.null(v) || !v %in% names(r$dt)) {
    dcc_abort("Check '", ch$id, "': variable '", v %||% "<missing>",
              "' not found.", class = "dcc_rule_error")
  }
  raw <- r$dt[[v]]
  raw_missing <- is.na(raw)
  vals <- suppressWarnings(as.numeric(as.character(raw)))
  invalid <- !raw_missing & is.na(vals)
  outside <- rep.int(FALSE, length(vals))
  if (!is.null(ch$min)) {
    outside <- outside | (!is.na(vals) & vals < ch$min)
  }
  if (!is.null(ch$max)) {
    outside <- outside | (!is.na(vals) & vals > ch$max)
  }
  hit <- which(invalid | outside)
  dcc_findings(
    record_id = r$ids[hit], variable = v, check_id = as.character(ch$id),
    evidence = ifelse(
      invalid[hit],
      sprintf("value '%s' is not numeric", as.character(raw[hit])),
      sprintf("value %s outside range [%s, %s]", format(vals[hit]),
              format(ch$min %||% -Inf), format(ch$max %||% Inf))
    ),
    severity = severity,
    dimension = if (is.na(dimension)) "validity" else dimension,
    code = ifelse(invalid[hit], "INVALID_NUMERIC", "OUT_OF_RANGE"),
    detector_id = "range"
  )
}

eval_set_check <- function(x, ch, id_var, severity, dimension) {
  r <- resolve_data(x, id_var)
  v <- ch$variable
  if (is.null(v) || !v %in% names(r$dt)) {
    dcc_abort("Check '", ch$id, "': variable '", v %||% "<missing>",
              "' not found.", class = "dcc_rule_error")
  }
  vals <- r$dt[[v]]
  allowed <- unlist(ch$values)
  bad <- !is.na(vals) & !(as.character(vals) %in% as.character(allowed))
  hit <- which(bad)
  dcc_findings(
    record_id = r$ids[hit], variable = v, check_id = as.character(ch$id),
    evidence = sprintf("value '%s' not in allowed set {%s}",
                       as.character(vals[hit]),
                       paste(allowed, collapse = ", ")),
    severity = severity,
    dimension = if (is.na(dimension)) "validity" else dimension
  )
}

# Restricted evaluation: data columns only, arithmetic/comparison/logic
# from base, no I/O and no assignment (design decision 1).
eval_expr_check <- function(x, ch, id_var, severity, dimension) {
  r <- resolve_data(x, id_var)
  if (is.null(ch$expr)) {
    dcc_abort("Check '", ch$id, "' of type expr needs an `expr` field.",
              class = "dcc_rule_error")
  }
  parsed <- tryCatch(
    parse(text = ch$expr, keep.source = FALSE),
    error = function(e) {
      dcc_abort("Check '", ch$id, "': cannot parse expr: ",
                conditionMessage(e), class = "dcc_rule_error")
    }
  )
  res <- tryCatch(
    eval(parsed, envir = r$dt, enclos = restricted_env()),
    error = function(e) {
      dcc_abort("Check '", ch$id, "': expr failed: ",
                conditionMessage(e), class = "dcc_rule_error")
    }
  )
  if (!is.logical(res)) {
    dcc_abort("Check '", ch$id, "': expr must evaluate to logical.",
              class = "dcc_rule_error")
  }
  res <- rep_len(res, nrow(r$dt))
  hit <- which(!is.na(res) & res)
  dcc_findings(
    record_id = r$ids[hit], variable = NA_character_,
    check_id = as.character(ch$id),
    evidence = paste0("expr is TRUE: ", ch$expr),
    severity = severity,
    dimension = if (is.na(dimension)) "consistency" else dimension
  )
}

restricted_env <- function() {
  allowed <- c(
    "+", "-", "*", "/", "^", "%%", "%/%",
    "==", "!=", "<", ">", "<=", ">=",
    "&", "|", "!", "&&", "||", "xor",
    "(", "[", "[[", "c", "is.na", "!is.na", "ifelse",
    "abs", "min", "max", "pmin", "pmax", "sum", "mean",
    "round", "floor", "ceiling", "sqrt", "exp", "log",
    "nchar", "substr", "grepl", "paste", "paste0", "%in%",
    "as.numeric", "as.character", "as.integer", "TRUE", "FALSE"
  )
  env <- new.env(parent = emptyenv())
  for (fn in allowed) {
    ok <- tryCatch({
      assign(fn, get(fn, envir = baseenv()), envir = env)
      TRUE
    }, error = function(e) FALSE)
    if (!ok) next
  }
  env
}
