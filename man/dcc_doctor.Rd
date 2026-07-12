% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/validate.R.
\name{dcc_doctor}
\alias{dcc_doctor}
\title{Run every validator over a dataset and rule set}
\usage{
dcc_doctor(data, rules, id_var = NULL)
}
\arguments{
\item{data}{A \code{dcc_data} or data.frame.}

\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{id_var}{Optional record-id column.}
}
\value{
A combined \code{dcc_validation} object.
}
\description{
Convenience wrapper: runs \code{\link{dcc_validate_rules}} and
\code{\link{dcc_validate_data}} and merges their reports.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    variable: score", "    min: 0", "    max: 100"), rf)
df <- data.frame(sid = c("S1", "S2"), score = c(50, 70))
if (requireNamespace("yaml", quietly = TRUE)) {
  dcc_doctor(df, dcc_rules(rf), id_var = "sid")
}
}
