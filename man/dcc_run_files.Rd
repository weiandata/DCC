% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/run.R.
\name{dcc_run_files}
\alias{dcc_run_files}
\title{Output files written by a run}
\usage{
dcc_run_files(x)
}
\arguments{
\item{x}{A \code{dcc_run} from \code{\link{dcc_run}}.}
}
\value{
A character vector of the file paths the run wrote.
}
\description{
Returns the output paths written by \code{\link{dcc_run}}.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    variable: score", "    min: 0", "    max: 100"), rf)
csv <- tempfile(fileext = ".csv")
writeLines(c("sid,score", "S1,90", "S2,150"), csv)
if (requireNamespace("yaml", quietly = TRUE)) {
  cfg <- dcc_config(dcc_rules(rf), id_var = "sid")
  dcc_run_files(dcc_run(csv, cfg, tempfile("dcc-out")))
}
}
