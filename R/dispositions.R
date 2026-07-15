#' Terminal dispositions of a cleaning result
#'
#' Returns one terminal disposition for every finding supplied to
#' [dcc_execute()]. Dispositions are the execution source of truth; the audit
#' log is checked against them by [dcc_reconcile()].
#'
#' @param x A `dcc_result` from [dcc_execute()].
#' @return A `data.table` with `finding_id`, `action`, `status`, and `message`.
#'   Status is one of `"changed"`, `"excluded"`, `"flagged"`, `"skipped"`,
#'   `"failed"`, or `"unhandled"`.
#' @export
dcc_dispositions <- function(x) {
  if (!inherits(x, "dcc_result")) {
    dcc_abort("`x` must be a dcc_result from dcc_execute().",
              class = "dcc_type_error")
  }
  data.table::copy(x$dispositions)
}

new_dispositions <- function(findings) {
  out <- data.table::data.table(
    finding_id = as.character(findings$finding_id),
    action = NA_character_,
    status = "unhandled",
    message = NA_character_
  )
  data.table::setattr(out, "class",
                      c("dcc_dispositions", class(data.table::data.table())))
  out
}
