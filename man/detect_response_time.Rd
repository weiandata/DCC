% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/detectors.R.
\name{detect_response_time}
\alias{detect_response_time}
\title{Detect implausibly fast or anomalous response times}
\usage{
detect_response_time(x, time_var, min_seconds = NULL,
  min_median_ratio = 1/3, id_var = NULL, severity = "warn")
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{time_var}{Name of the total response-time column (numeric,
seconds).}

\item{min_seconds}{Absolute minimum plausible total time, or
\code{NULL} to skip the absolute check.}

\item{min_median_ratio}{Flag times below this fraction of the median
(default 1/3), or \code{NULL} to skip the relative check.}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}

\item{severity}{Severity assigned to findings (default \code{"warn"}).}
}
\value{
A \code{\link{dcc_findings}} table (check id \code{Q_RESPONSE_TIME}).
}
\description{
Flags respondents whose total response time is below an absolute
minimum, or below a fraction of the median time. Each finding's
evidence states which cut was triggered.
}
\examples{
df <- data.frame(sid = c("S1", "S2", "S3"),
                 time_total = c(600, 45, 590))
detect_response_time(df, "time_total", min_seconds = 60, id_var = "sid")
}
