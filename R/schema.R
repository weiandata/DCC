#' Published JSON Schema for a DCC object
#'
#' Returns the formal JSON Schema (draft-07) for one of DCC's public
#' objects. The schemas are versioned artifacts installed with the
#' package under `inst/schemas/`, so AI systems and external validators
#' can check a rule file, action map, findings table, audit log, or
#' manifest against a stable contract.
#'
#' @param name One of `"finding"`, `"disposition"`, `"provenance"`,
#'   `"audit_log"`, `"rules"`, `"actions"`, `"manifest"`, or `"plan"`.
#' @param as `"object"` (default) returns the parsed schema (requires
#'   the `jsonlite` package); `"path"` returns the installed file path.
#' @return The parsed schema (a list) or the schema file path.
#' @examples
#' dcc_schema("finding", as = "path")
#' if (requireNamespace("jsonlite", quietly = TRUE)) {
#'   dcc_schema("actions")$title
#' }
#' @export
dcc_schema <- function(name, as = c("object", "path")) {
  as <- match.arg(as)
  files <- c(finding = "finding", disposition = "disposition",
             provenance = "provenance", audit_log = "audit-log",
             rules = "rules", actions = "actions", manifest = "manifest",
             plan = "plan")
  name <- match.arg(name, names(files))
  file <- system.file("schemas", paste0(files[[name]], ".schema.json"),
                      package = "DCC")
  if (!nzchar(file)) {
    dcc_abort("Schema '", name, "' not found in the installed package.",
              class = "dcc_io_error")
  }
  if (identical(as, "path")) {
    return(file)
  }
  jsonlite::fromJSON(file, simplifyVector = TRUE)
}
