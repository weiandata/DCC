% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/validate.R.
\name{dcc_validate_data}
\alias{dcc_validate_data}
\title{Validate data against a rule set before detection}
\usage{
dcc_validate_data(data, rules = NULL, id_var = NULL)
}
\arguments{
\item{data}{A \code{dcc_data} or data.frame.}

\item{rules}{Optional \code{dcc_ruleset}; when supplied, referenced
variables are checked against the data columns.}

\item{id_var}{Optional record-id column to check for presence,
missingness, and duplication.}
}
\value{
A \code{dcc_validation} object (see \code{\link{dcc_validate_rules}}).
}
\description{
Checks that a dataset can carry a cleaning run: the record-id column is
present, non-missing, and unique, and every variable a rule references
exists. It never changes the data.
}
\examples{
df <- data.frame(sid = c("S1", "S1", "S2"), score = c(50, 150, 70))
dcc_validate_data(df, id_var = "sid")
}
\seealso{
\code{\link{dcc_validate_rules}}, \code{\link{dcc_doctor}}.
}
