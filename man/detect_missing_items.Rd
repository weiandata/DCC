% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/detectors.R.
\name{detect_missing_items}
\alias{detect_missing_items}
\title{Detect excessive item nonresponse per respondent}
\usage{
detect_missing_items(x, items, max_prop = 0.5, id_var = NULL,
  severity = "warn", structural = NULL)
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{items}{Character vector of item column names.}

\item{max_prop}{Maximum tolerated missing proportion (default 0.5).}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}

\item{severity}{Severity assigned to findings (default \code{"warn"}).}

\item{structural}{Optional logical matrix (rows aligned to the data,
columns to \code{items}) marking cells that were \emph{not administered}
-- e.g. from a \code{skip_logic} rule. Not-administered cells are
excluded from both the numerator and denominator of the missing
proportion. \code{NULL} (default) treats every item as administered and
is byte-identical to the pre-1.1.0 behaviour.}
}
\value{
A \code{\link{dcc_findings}} table (check id \code{Q_MISSING_ITEMS},
dimension \code{completeness}).
}
\description{
Flags respondents whose proportion of missing item responses exceeds
\code{max_prop}. Like all detectors, it only finds; exclusion happens
in the Execute stage.
}
\examples{
df <- data.frame(sid = c("S1", "S2"),
                 q1 = c(1, NA), q2 = c(2, NA), q3 = c(3, 1))
detect_missing_items(df, c("q1", "q2", "q3"), max_prop = 0.5,
                     id_var = "sid")
}
