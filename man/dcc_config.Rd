% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/run.R.
\name{dcc_config}
\alias{dcc_config}
\title{A cleaning configuration}
\usage{
dcc_config(rules, actions = list(), id_var = NULL, items = NULL)
}
\arguments{
\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{actions}{Named list mapping \code{check_id}s to actions (see
\code{\link{dcc_execute}}).}

\item{id_var}{Record-id column name, or \code{NULL} for row numbers.}

\item{items}{Optional character vector of item column names.}
}
\value{
A \code{dcc_config} object.
}
\description{
Bundles a rule set, an action map, a record-id column, and the item
columns into a single object that \code{\link{dcc_run}} consumes.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    variable: score", "    min: 0", "    max: 100"), rf)
if (requireNamespace("yaml", quietly = TRUE)) {
  dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"), id_var = "sid")
}
}
\seealso{
\code{\link{dcc_run}}, \code{\link{dcc_validate_config}}.
}
