\name{dcc_missing_states}
\alias{dcc_missing_states}
\title{Canonical cell-level missing states}
\usage{
dcc_missing_states(x)
}
\arguments{
\item{x}{A \code{dcc_data} object.}
}
\value{
A copy of the cell-level missing-state table.
}
\description{
Returns explicit missing semantics for imported and cleaned cells, including
not administered, respondent omission, import missing, declared missing code,
and cleared by cleaning.
}
