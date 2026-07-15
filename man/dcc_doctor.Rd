% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/validate.R.
\name{dcc_doctor}
\alias{dcc_doctor}
\title{Run every validator over a dataset and rule set}
\usage{
dcc_doctor(data = NULL, rules = NULL, id_var = NULL, formats = NULL)
}
\arguments{
\item{data}{Optional \code{dcc_data} or data.frame.}

\item{rules}{Optional \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{id_var}{Optional record-id column.}

\item{formats}{\code{NULL}, \code{"all"}, or registered format names whose
installed backends and platform limitations should be checked.}
}
\value{
A combined \code{dcc_validation} object.
}
\description{
Runs the requested rule, data, and registered-format backend checks and merges
their structured reports without changing data or files.
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
