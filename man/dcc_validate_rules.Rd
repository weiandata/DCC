% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/validate.R.
\name{dcc_validate_rules}
\alias{dcc_validate_rules}
\title{Validate a rule set before it is used}
\usage{
dcc_validate_rules(rules)
}
\arguments{
\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}} (or the
\code{rules} element of a \code{dcc_config}).}
}
\value{
A \code{dcc_validation} object: a \code{data.table} with \code{code},
\code{severity}, \code{field}, \code{rows} (affected row indices, a list
column), \code{fix}, and optional workbook location fields \code{workbook},
\code{sheet}, \code{row}, \code{column}, and \code{cell}.
}
\description{
Checks a \code{\link{dcc_rules}} rule set for structural problems --
unknown types, missing required fields, duplicate or empty IDs -- and
returns a structured report. It never evaluates rules against data and
never changes anything.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    min: 0", "    max: 100"), rf)
if (requireNamespace("yaml", quietly = TRUE)) {
  dcc_validate_rules(dcc_rules(rf))
}
}
\seealso{
\code{\link{dcc_validate_data}}, \code{\link{dcc_doctor}}.
}
