#' Findings left unhandled by execution
#'
#' Returns the findings that had no explicit action in [dcc_execute()]
#' and were therefore neither changed nor dispositioned. This is the
#' public accessor for the result's unhandled set; callers should not
#' read the underlying list element directly.
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @return A [dcc_findings()] table (possibly empty) of unhandled
#'   findings.
#' @examples
#' df <- data.frame(sid = "S1", q1 = 9)
#' f <- dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e")
#' res <- dcc_execute(df, f, actions = list(), id_var = "sid")
#' dcc_unhandled(res)
#' @export
dcc_unhandled <- function(x) {
  if (!inherits(x, "dcc_result")) {
    dcc_abort("`x` must be a dcc_result from dcc_execute().",
              class = "dcc_type_error")
  }
  x$unhandled
}

#' Master item map of a form-mapped dataset
#'
#' Returns the resolved form-to-master item map attached by
#' [dcc_map_forms()]. This is the public accessor for the mapping;
#' callers should not read the hidden attribute directly.
#'
#' @param x A `dcc_data` returned by [dcc_map_forms()].
#' @return The item-map `data.frame` (`master`, `form`, `source`,
#'   `is_anchor`, ...).
#' @examples
#' data <- data.frame(sid = c("S1", "S2"), form = c("A", "B"),
#'                    p1 = c(1, 2), p2 = c(5, 6))
#' fmap <- data.frame(form = c("A", "A", "B", "B"),
#'                    source = c("p1", "p2", "p1", "p2"),
#'                    master = c("M001", "M002", "M003", "M002"),
#'                    is_anchor = c(FALSE, TRUE, FALSE, TRUE))
#' mapped <- dcc_map_forms(data, fmap, form_var = "form")
#' dcc_item_map(mapped)
#' @export
dcc_item_map <- function(x) {
  m <- attr(x, "dcc_item_map", exact = TRUE)
  if (is.null(m)) {
    dcc_abort("`x` has no item map; pass a dcc_map_forms() result.",
              class = "dcc_type_error")
  }
  m
}

#' Mapping problems found while aligning forms
#'
#' Returns the [dcc_findings()] table of mapping problems (unknown forms,
#' missing source items) attached by [dcc_map_forms()]. This is the
#' public accessor; callers should not read the hidden attribute
#' directly.
#'
#' @param x A `dcc_data` returned by [dcc_map_forms()].
#' @return A [dcc_findings()] table (possibly empty).
#' @examples
#' data <- data.frame(sid = c("S1", "S2"), form = c("A", "B"),
#'                    p1 = c(1, 2), p2 = c(5, 6))
#' fmap <- data.frame(form = c("A", "A", "B", "B"),
#'                    source = c("p1", "p2", "p1", "p2"),
#'                    master = c("M001", "M002", "M003", "M002"),
#'                    is_anchor = c(FALSE, TRUE, FALSE, TRUE))
#' mapped <- dcc_map_forms(data, fmap, form_var = "form")
#' dcc_mapping_findings(mapped)
#' @export
dcc_mapping_findings <- function(x) {
  f <- attr(x, "dcc_findings", exact = TRUE)
  if (is.null(f)) {
    dcc_abort("`x` has no mapping findings; pass a dcc_map_forms() result.",
              class = "dcc_type_error")
  }
  f
}
