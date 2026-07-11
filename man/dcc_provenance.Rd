% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/dcc_data.R.
\name{dcc_provenance}
\alias{dcc_provenance}
\title{Provenance chain of a dcc_data object}
\usage{
dcc_provenance(x)
}
\arguments{
\item{x}{A \code{dcc_data} object.}
}
\value{
A \code{data.table} with one row per provenance record: \code{stage},
\code{timestamp}, \code{dcc_version}, and a list-column \code{details}.
}
\description{
Returns the append-only provenance chain recording every stage the
object has passed through (read, detect, execute, ...). This chain is
the backbone of DCC's auditable-reporting guarantee: any dataset version
can be traced back to its source file and rule versions.
}
\examples{
x <- dcc_data(data.frame(id = 1:2))
dcc_provenance(x)
}
