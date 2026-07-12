% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/rerun.R.
\name{dcc_rerun}
\alias{dcc_rerun}
\title{Re-run a cleaning pipeline from its manifest and verify the output}
\usage{
dcc_rerun(manifest)
}
\arguments{
\item{manifest}{A \code{dcc_manifest}, a \code{dcc_result} (a manifest
is built from it first), or a path to a manifest YAML file.}
}
\value{
A \code{dcc_rerun} object: list with \code{reproduced} (logical),
\code{data_match}, \code{audit_match}, and the re-run \code{result}.
}
\description{
Implements one-command reproducibility (design principle 7): reads the
raw input again and verifies its hash, reloads and verifies the rule
file, re-runs detect and execute with the recorded actions, and
compares the cleaned data and audit log (excluding timestamps) against
the manifest hashes. An input or rule file whose hash no longer
matches raises a typed error -- changed inputs make reproduction
claims meaningless.
}
\seealso{
\code{\link{dcc_manifest}}
}
