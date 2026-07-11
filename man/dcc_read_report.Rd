% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/dcc_data.R.
\name{dcc_read_report}
\alias{dcc_read_report}
\title{Read report of a dcc_data object}
\usage{
dcc_read_report(x)
}
\arguments{
\item{x}{A \code{dcc_data} object.}
}
\value{
The \code{dcc_read_report} attached at read time (see
\code{\link{dcc_l0_diagnose}}), or \code{NULL} if the object was not
created by \code{\link{dcc_read}}.
}
\description{
Accessor for the level-0 read report produced by \code{\link{dcc_read}}:
dimensions, per-column profile, encoding information, and structural
findings.
}
\examples{
f <- tempfile(fileext = ".csv")
writeLines(c("id,score", "S1,90"), f)
dcc_read_report(dcc_read(f))
}
