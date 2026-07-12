#' Built-in response-quality detectors
#'
#' The five v1-core detectors flag suspect respondents and emit a
#' [dcc_findings()] table. Detectors only *find*; they never modify data
#' (exclusion happens in the Execute stage, keeping the audit loop
#' closed).
#'
#' All detectors accept either a [dcc_data()] object or a plain
#' `data.frame`, and identify records by `id_var` (row number when
#' `NULL`).
#'
#' @name detectors
#' @keywords internal
NULL

#' Detect excessive item nonresponse per respondent
#'
#' Flags respondents whose proportion of missing item responses exceeds
#' `max_prop`.
#'
#' @param x A `dcc_data` object or data.frame.
#' @param items Character vector of item column names.
#' @param max_prop Maximum tolerated missing proportion (default 0.5).
#' @param id_var Name of the record-id column, or `NULL` for row numbers.
#' @param severity Severity assigned to findings (default `"warn"`).
#' @param structural Optional logical matrix (rows aligned to the data,
#'   columns to `items`) marking cells that were *not administered* --
#'   e.g. from a `skip_logic` rule. Not-administered cells are excluded
#'   from both the numerator and the denominator of the missing
#'   proportion, so a legitimately skipped item is not counted as
#'   missingness. `NULL` (default) treats every item as administered and
#'   is byte-identical to the pre-1.1.0 behaviour.
#' @return A [dcc_findings()] table (check id `Q_MISSING_ITEMS`).
#' @export
detect_missing_items <- function(x, items, max_prop = 0.5, id_var = NULL,
                                 severity = "warn", structural = NULL) {
  r <- resolve_data(x, id_var)
  m <- resolve_items(r$dt, items)
  if (is.null(structural)) {
    prop <- rowMeans(is.na(m))
    hit <- which(prop > max_prop)
    evidence <- sprintf("%.0f%% of %d items missing (max %.0f%%)",
                        100 * prop[hit], length(items), 100 * max_prop)
  } else {
    administered <- !structural
    n_admin <- rowSums(administered)
    n_missing <- rowSums(is.na(m) & administered)
    prop <- ifelse(n_admin > 0L, n_missing / n_admin, 0)
    hit <- which(prop > max_prop)
    evidence <- sprintf("%.0f%% of %d administered items missing (max %.0f%%)",
                        100 * prop[hit], n_admin[hit], 100 * max_prop)
  }
  dcc_findings(
    record_id = r$ids[hit],
    check_id = "Q_MISSING_ITEMS",
    evidence = evidence,
    severity = severity,
    dimension = "completeness"
  )
}

#' Detect straight-lining (longstring)
#'
#' Computes the longest run of identical consecutive item responses per
#' respondent (the longstring index; cf. the CRAN package `careless`)
#' and flags respondents whose run meets or exceeds `max_run`.
#'
#' @inheritParams detect_missing_items
#' @param max_run Minimum run length considered straight-lining
#'   (default 10).
#' @param na_breaks_run Should a missing response break a run?
#'   (default `TRUE`).
#' @return A [dcc_findings()] table (check id `Q_STRAIGHTLINING`).
#' @export
detect_straightlining <- function(x, items, max_run = 10L, id_var = NULL,
                                  severity = "warn", na_breaks_run = TRUE) {
  r <- resolve_data(x, id_var)
  m <- resolve_items(r$dt, items)
  k <- ncol(m)
  if (k < 2L) {
    return(empty_findings())
  }
  # Vectorized over rows: walk columns once, tracking current/max runs.
  eq <- m[, -1L, drop = FALSE] == m[, -k, drop = FALSE]
  if (na_breaks_run) {
    eq[is.na(eq)] <- FALSE
  } else {
    both_na <- is.na(m[, -1L, drop = FALSE]) & is.na(m[, -k, drop = FALSE])
    eq[is.na(eq)] <- FALSE
    eq <- eq | both_na
  }
  cur <- rep.int(1L, nrow(m))
  max_run_len <- cur
  for (j in seq_len(ncol(eq))) {
    cur <- ifelse(eq[, j], cur + 1L, 1L)
    max_run_len <- pmax(max_run_len, cur)
  }
  hit <- which(max_run_len >= max_run)
  dcc_findings(
    record_id = r$ids[hit],
    check_id = "Q_STRAIGHTLINING",
    evidence = sprintf("longest identical-response run %d of %d items (limit %d)",
                       max_run_len[hit], k, max_run),
    severity = severity,
    dimension = "accuracy"
  )
}

#' Detect implausibly fast or anomalous response times
#'
#' Flags respondents whose total response time is below an absolute
#' minimum, or below a fraction of the median time.
#'
#' @inheritParams detect_missing_items
#' @param time_var Name of the total response-time column (numeric,
#'   seconds).
#' @param min_seconds Absolute minimum plausible total time, or `NULL`
#'   to skip.
#' @param min_median_ratio Flag times below this fraction of the median
#'   (default 1/3), or `NULL` to skip.
#' @return A [dcc_findings()] table (check id `Q_RESPONSE_TIME`).
#' @export
detect_response_time <- function(x, time_var, min_seconds = NULL,
                                 min_median_ratio = 1 / 3, id_var = NULL,
                                 severity = "warn") {
  r <- resolve_data(x, id_var)
  if (!time_var %in% names(r$dt)) {
    dcc_abort("`time_var` '", time_var, "' not found in data.",
              class = "dcc_type_error")
  }
  tt <- as.numeric(r$dt[[time_var]])
  reasons <- rep.int(NA_character_, length(tt))
  if (!is.null(min_seconds)) {
    hit_abs <- !is.na(tt) & tt < min_seconds
    reasons[hit_abs] <- sprintf("total time %.0fs below absolute minimum %.0fs",
                                tt[hit_abs], min_seconds)
  }
  if (!is.null(min_median_ratio)) {
    med <- stats::median(tt, na.rm = TRUE)
    cut <- med * min_median_ratio
    hit_rel <- !is.na(tt) & tt < cut & is.na(reasons)
    reasons[hit_rel] <- sprintf(
      "total time %.0fs below %.0f%% of median (%.0fs)",
      tt[hit_rel], 100 * min_median_ratio, med
    )
  }
  hit <- which(!is.na(reasons))
  dcc_findings(
    record_id = r$ids[hit],
    variable = time_var,
    check_id = "Q_RESPONSE_TIME",
    evidence = reasons[hit],
    severity = severity,
    dimension = "accuracy"
  )
}

#' Detect failed trap (attention-check) items
#'
#' Compares responses on designated trap items with their expected
#' values and flags respondents failing at least `max_failed` traps.
#'
#' @inheritParams detect_missing_items
#' @param traps Named list or named vector: names are trap item columns,
#'   values the expected response.
#' @param max_failed Number of failed traps that triggers a finding
#'   (default 1).
#' @param na_fails Should a missing response on a trap item count as a
#'   failure? (default `TRUE`).
#' @return A [dcc_findings()] table (check id `Q_TRAP_ITEMS`).
#' @export
detect_trap_items <- function(x, traps, max_failed = 1L, id_var = NULL,
                              severity = "fail", na_fails = TRUE) {
  r <- resolve_data(x, id_var)
  trap_items <- names(traps)
  if (is.null(trap_items) || any(!nzchar(trap_items))) {
    dcc_abort("`traps` must be a named list/vector: names are item ",
              "columns, values the expected response.",
              class = "dcc_type_error")
  }
  m <- resolve_items(r$dt, trap_items)
  fails <- matrix(FALSE, nrow(m), ncol(m))
  for (j in seq_along(trap_items)) {
    exp_val <- traps[[j]]
    fj <- m[, j] != exp_val
    fj[is.na(fj)] <- na_fails
    fails[, j] <- fj
  }
  n_failed <- rowSums(fails)
  hit <- which(n_failed >= max_failed)
  dcc_findings(
    record_id = r$ids[hit],
    check_id = "Q_TRAP_ITEMS",
    evidence = sprintf("failed %d of %d trap item(s) (limit %d)",
                       n_failed[hit], length(trap_items), max_failed),
    severity = severity,
    dimension = "accuracy"
  )
}

#' Detect group-wise score anomalies
#'
#' Flags respondents whose score is an outlier within their group
#' (IQR fences or z-scores), and groups whose mean deviates strongly
#' from the overall mean.
#'
#' @inheritParams detect_missing_items
#' @param score_var Name of the numeric score column.
#' @param group_vars Character vector of grouping columns; `NULL` treats
#'   the data as one group.
#' @param method `"iqr"` (default) or `"zscore"` for within-group
#'   outliers.
#' @param k Fence multiplier: IQR multiplier (default 1.5) or |z|
#'   cutoff (use e.g. 3 with `method = "zscore"`).
#' @param group_mean_z Flag groups whose mean is more than this many
#'   overall standard deviations from the overall mean (default 2;
#'   `NULL` skips the group-level check).
#' @return A [dcc_findings()] table (check ids `Q_SCORE_OUTLIER` and
#'   `Q_GROUP_SCORE_SHIFT`; group-level findings have
#'   `record_id = NA` and the group label in `evidence`).
#' @export
detect_score_anomaly <- function(x, score_var, group_vars = NULL,
                                 method = c("iqr", "zscore"), k = 1.5,
                                 group_mean_z = 2, id_var = NULL,
                                 severity = "warn") {
  method <- match.arg(method)
  r <- resolve_data(x, id_var)
  if (!score_var %in% names(r$dt)) {
    dcc_abort("`score_var` '", score_var, "' not found in data.",
              class = "dcc_type_error")
  }
  dt <- data.table::copy(r$dt)
  dt[, `.dcc_id` := r$ids]
  dt[, `.dcc_score` := as.numeric(dt[[score_var]])]
  if (is.null(group_vars)) {
    dt[, `.dcc_group` := "all"]
    group_vars_eff <- ".dcc_group"
  } else {
    missing_cols <- setdiff(group_vars, names(dt))
    if (length(missing_cols)) {
      dcc_abort("Group column(s) not found: ",
                paste(missing_cols, collapse = ", "),
                class = "dcc_type_error")
    }
    group_vars_eff <- group_vars
  }

  if (method == "iqr") {
    dt[, `:=`(
      .dcc_lo = stats::quantile(`.dcc_score`, 0.25, na.rm = TRUE) -
        k * stats::IQR(`.dcc_score`, na.rm = TRUE),
      .dcc_hi = stats::quantile(`.dcc_score`, 0.75, na.rm = TRUE) +
        k * stats::IQR(`.dcc_score`, na.rm = TRUE)
    ), by = group_vars_eff]
    out_idx <- which(!is.na(dt$`.dcc_score`) &
                       (dt$`.dcc_score` < dt$`.dcc_lo` |
                          dt$`.dcc_score` > dt$`.dcc_hi`))
    ev <- sprintf("score %.2f outside group IQR fences [%.2f, %.2f]",
                  dt$`.dcc_score`[out_idx], dt$`.dcc_lo`[out_idx],
                  dt$`.dcc_hi`[out_idx])
  } else {
    dt[, `:=`(
      .dcc_mu = mean(`.dcc_score`, na.rm = TRUE),
      .dcc_sd = stats::sd(`.dcc_score`, na.rm = TRUE)
    ), by = group_vars_eff]
    z <- (dt$`.dcc_score` - dt$`.dcc_mu`) / dt$`.dcc_sd`
    out_idx <- which(!is.na(z) & abs(z) > k)
    ev <- sprintf("score %.2f has within-group |z| = %.2f (limit %.2f)",
                  dt$`.dcc_score`[out_idx], abs(z[out_idx]), k)
  }
  person <- dcc_findings(
    record_id = dt$`.dcc_id`[out_idx],
    variable = score_var,
    check_id = "Q_SCORE_OUTLIER",
    evidence = ev,
    severity = severity,
    dimension = "accuracy"
  )

  group <- NULL
  if (!is.null(group_mean_z) && !is.null(group_vars)) {
    overall_mu <- mean(dt$`.dcc_score`, na.rm = TRUE)
    overall_sd <- stats::sd(dt$`.dcc_score`, na.rm = TRUE)
    gm <- dt[, list(.dcc_gmu = mean(`.dcc_score`, na.rm = TRUE)),
             by = group_vars_eff]
    gz <- (gm$`.dcc_gmu` - overall_mu) / overall_sd
    g_idx <- which(!is.na(gz) & abs(gz) > group_mean_z)
    if (length(g_idx)) {
      labels <- apply(
        gm[g_idx, group_vars_eff, with = FALSE], 1L,
        function(row) paste(group_vars_eff, row, sep = "=", collapse = ", ")
      )
      group <- dcc_findings(
        record_id = NA_character_,
        variable = score_var,
        check_id = "Q_GROUP_SCORE_SHIFT",
        evidence = sprintf(
          "group (%s) mean %.2f is %.2f overall SDs from overall mean %.2f",
          labels, gm$`.dcc_gmu`[g_idx], abs(gz[g_idx]), overall_mu
        ),
        severity = severity,
        dimension = "consistency"
      )
    }
  }
  bind_findings(list(person, group))
}
