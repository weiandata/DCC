% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/l0_diagnostics.R.
\name{dcc_l0_diagnose}
\alias{dcc_l0_diagnose}
\title{Level-0 structural diagnostics}
\usage{
dcc_l0_diagnose(data, meta = list())
}
\arguments{
\item{data}{A \code{data.frame} or \code{data.table}.}

\item{meta}{Optional metadata list from \code{\link{dcc_read}} (used for
encoding-confidence findings).}
}
\value{
A \code{dcc_read_report} object: a list with \code{n_rows},
\code{n_cols}, \code{columns} (per-column profile), and \code{findings}
(L0 findings table with columns \code{check_id}, \code{severity},
\code{variable}, \code{evidence}).
}
\description{
Runs Eurostat-style level-0 (structural) validation on a freshly read
table: dimensions, per-column type and missingness profile, duplicate or
empty column names, all-missing columns and rows, and encoding
confidence. Findings use the same shape as later detection stages so the
read report feeds the same audit pipeline.
}
\examples{
rep <- dcc_l0_diagnose(data.frame(a = c(1, NA), b = c(NA, NA)))
rep$findings
}
