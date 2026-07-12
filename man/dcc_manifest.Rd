% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/rerun.R.
\name{dcc_manifest}
\alias{dcc_manifest}
\title{Build a reproducibility manifest for a cleaning run}
\usage{
dcc_manifest(x, path = NULL)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}, produced
from a \code{\link{dcc_read}} input and \code{\link{dcc_detect}}
findings (so input and rule sources are known).}

\item{path}{Optional path to write the manifest as YAML (requires the
\pkg{yaml} package).}
}
\value{
A \code{dcc_manifest} object (named list with input, ruleset, action
and output-hash sections), invisibly written to \code{path} when
given.
}
\description{
Captures everything needed to re-execute the read -> detect -> execute
pipeline and verify byte-identical results: input file path and hash,
rule file path and hash, the executed actions, id/default
configuration, and content hashes of the cleaned data and the audit
log (timestamps excluded).
}
\seealso{
\code{\link{dcc_rerun}}
}
