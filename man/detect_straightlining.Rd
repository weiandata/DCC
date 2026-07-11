% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/detectors.R.
\name{detect_straightlining}
\alias{detect_straightlining}
\title{Detect straight-lining (longstring)}
\usage{
detect_straightlining(x, items, max_run = 10L, id_var = NULL,
  severity = "warn", na_breaks_run = TRUE)
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{items}{Character vector of item column names, in presentation
order.}

\item{max_run}{Minimum run length considered straight-lining
(default 10).}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}

\item{severity}{Severity assigned to findings (default \code{"warn"}).}

\item{na_breaks_run}{Should a missing response break a run?
(default \code{TRUE}).}
}
\value{
A \code{\link{dcc_findings}} table (check id \code{Q_STRAIGHTLINING}).
}
\description{
Computes the longest run of identical consecutive item responses per
respondent (the longstring index; cf. the CRAN package
\pkg{careless}) and flags respondents whose run meets or exceeds
\code{max_run}. The computation is vectorized over respondents.
}
\examples{
df <- data.frame(sid = c("S1", "S2"),
                 q1 = c(1, 4), q2 = c(2, 4), q3 = c(1, 4), q4 = c(3, 4))
detect_straightlining(df, paste0("q", 1:4), max_run = 4, id_var = "sid")
}
