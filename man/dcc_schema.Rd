% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/schema.R.
\name{dcc_schema}
\alias{dcc_schema}
\title{Published JSON Schema for a DCC object}
\usage{
dcc_schema(name, as = c("object", "path"))
}
\arguments{
\item{name}{One of \code{"finding"}, \code{"disposition"},
\code{"provenance"}, \code{"audit_log"}, \code{"rules"},
\code{"actions"}, \code{"manifest"}, or \code{"plan"}.}

\item{as}{\code{"object"} (default) returns the parsed schema (requires
the \code{jsonlite} package); \code{"path"} returns the installed file
path.}
}
\value{
The parsed schema (a list) or the schema file path.
}
\description{
Returns the formal JSON Schema (draft-07) for one of DCC's public
objects. The schemas are versioned artifacts installed with the package
under \code{inst/schemas/}, so AI systems and external validators can
check a strict plan, rule file, action map, findings table, disposition,
provenance, audit log, or manifest
against a stable contract.
}
\examples{
dcc_schema("finding", as = "path")
if (requireNamespace("jsonlite", quietly = TRUE)) {
  dcc_schema("actions")$title
}
}
\seealso{
\code{\link{dcc_capabilities}} for the capability document.
}
