% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/dcc_data.R.
\name{dcc_data}
\alias{dcc_data}
\title{The dcc_data container}
\usage{
dcc_data(data, meta = list(), read_report = NULL, provenance = NULL,
  dictionary = NULL, missing_states = NULL, import_spec = NULL)
}
\arguments{
\item{data}{A \code{data.frame} or \code{data.table}.}

\item{meta}{Named list of source metadata (see \code{\link{dcc_read}}).}

\item{read_report}{A \code{dcc_read_report} object, or \code{NULL}.}

\item{provenance}{List of provenance records; normally created
internally.}

\item{dictionary}{Canonical variable dictionary with unique \code{name}
values.}

\item{missing_states}{Cell-level missing-state table using DCC's declared
missing-state vocabulary.}

\item{import_spec}{The \code{dcc_import_spec} that produced the canonical
data, or \code{NULL} for data created directly in R.}
}
\value{
An object of class \code{dcc_data}: a list with elements \code{data}
(a \code{data.table}), \code{meta}, \code{read_report}, \code{provenance},
\code{dictionary}, \code{missing_states}, and \code{import_spec}.
}
\description{
A \code{dcc_data} object bundles the dataset with its metadata, the
level-0 read report, and an append-only provenance chain. Every DCC
stage (detect, execute, report) receives and returns this container;
stages append to the provenance chain and never rewrite it (raw data is
immutable; cleaning produces new versions).
}
\examples{
x <- dcc_data(data.frame(id = 1:3, score = c(90, 85, 77)))
dcc_provenance(x)
}
