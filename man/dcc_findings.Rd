% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/findings.R.
\name{dcc_findings}
\alias{dcc_findings}
\title{The dcc_findings table}
\usage{
dcc_findings(record_id = character(), variable = NA_character_,
  check_id = character(), evidence = character(), severity = "warn",
  dimension = NA_character_, run_id = "manual")
}
\arguments{
\item{record_id}{Character vector (or coercible) of record ids.}

\item{variable}{Character vector of affected variables, or \code{NA}.}

\item{check_id}{Character vector of check identifiers.}

\item{evidence}{Character vector describing the measured evidence.}

\item{severity}{One of \code{"info"}, \code{"warn"}, \code{"fail"}
(recycled).}

\item{dimension}{Quality dimension label (recycled).}

\item{run_id}{One non-empty run identifier used to make finding IDs stable.}
}
\value{
A \code{dcc_findings} object (also a \code{data.table}).
}
\description{
A \code{dcc_findings} object is the structured violation list produced
by the Detect stage and consumed by the Execute stage: columns
\code{finding_id}, \code{record_id}, \code{variable}, \code{check_id},
\code{evidence}, \code{severity} and \code{dimension}. The additive
\code{finding_id} is deterministic within a run and includes the rule,
record, variable, and occurrence. It is the single interface
between detection and execution in the Detect-Execute-Report workflow.
}
\examples{
dcc_findings(record_id = "S001", check_id = "R001",
             evidence = "value 7 outside range [1, 5]",
             severity = "fail", dimension = "validity")
}
