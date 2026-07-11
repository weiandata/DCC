% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/detectors.R.
\name{detect_trap_items}
\alias{detect_trap_items}
\title{Detect failed trap (attention-check) items}
\usage{
detect_trap_items(x, traps, max_failed = 1L, id_var = NULL,
  severity = "fail", na_fails = TRUE)
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{traps}{Named list or named vector: names are trap item columns,
values the expected response.}

\item{max_failed}{Number of failed traps that triggers a finding
(default 1).}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}

\item{severity}{Severity assigned to findings (default \code{"fail"}).}

\item{na_fails}{Should a missing response on a trap item count as a
failure? (default \code{TRUE}).}
}
\value{
A \code{\link{dcc_findings}} table (check id \code{Q_TRAP_ITEMS}).
}
\description{
Compares responses on designated trap (attention-check) items with
their expected values and flags respondents failing at least
\code{max_failed} traps. Trap definitions are typically maintained in
an external, versioned key file.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), trap1 = c(3, 5))
detect_trap_items(df, traps = list(trap1 = 3), id_var = "sid")
}
