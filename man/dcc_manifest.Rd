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
\examples{
csv <- tempfile(fileext = ".csv")
writeLines(c("sid,score", "S1,90", "S2,150"), csv)
rules_file <- tempfile(fileext = ".yaml")
writeLines(c(
  "checks:",
  "  - id: R001",
  "    type: range",
  "    variable: score",
  "    min: 0",
  "    max: 100"
), rules_file)
if (requireNamespace("yaml", quietly = TRUE)) {
  x <- dcc_read(csv)
  f <- dcc_detect(x, dcc_rules(rules_file), id_var = "sid")
  res <- dcc_execute(x, f, actions = list(R001 = "set_na"),
                     id_var = "sid")
  dcc_manifest(res)
}
}
\seealso{
\code{\link{dcc_rerun}}
}
