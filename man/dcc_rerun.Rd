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
  # re-run from the manifest and confirm byte-identical reproduction
  dcc_rerun(dcc_manifest(res))$reproduced
}
}
\seealso{
\code{\link{dcc_manifest}}
}
