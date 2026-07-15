% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/run.R.
\name{dcc_run}
\alias{dcc_run}
\title{Run a cleaning workflow with one command}
\usage{
dcc_run(data, config = NULL, output_dir = "dcc-results",
  mode = c("preview", "execute", "verify", "rerun"), id_var = NULL,
  plan = NULL)
}
\arguments{
\item{data}{A data file path, a \code{dcc_data}, or a data.frame (or a
manifest path in \code{"rerun"} mode).}

\item{config}{Optional \code{dcc_config} from \code{\link{dcc_config}}.
Supply this or \code{plan}, not both.}

\item{output_dir}{Directory for the fixed output layout (created if
needed).}

\item{mode}{One of \code{"preview"} (default), \code{"execute"},
\code{"verify"}, \code{"rerun"}.}

\item{id_var}{Record-id column; defaults to the config's \code{id_var}.}

\item{plan}{Optional strict \code{.xlsx}/\code{.json} plan path or
\code{dcc_plan}.}
}
\value{
A \code{dcc_run} object with the mode, config, and written file paths
(via \code{\link{dcc_run_files}}).
}
\description{
The survey-staff entry point: orchestrates the Detect -> Execute ->
Report pipeline from a \code{\link{dcc_config}} or strict plan and writes a fixed
output layout. Preview is the default, so the safe path requires no
extra care, and the raw input file is never modified in any mode. Files are
written to a same-parent staging directory and published atomically. Existing
output directories are never overwritten; failed runs publish a diagnostic
\code{.failed-<run_id>} directory and raise \code{dcc_run_error}.
}
\details{
Modes: \code{"preview"} detects and reports only (no data change, no
\code{cleaned-data.csv}); \code{"execute"} applies the configured
actions and writes the cleaned data, audit log, and manifest;
\code{"verify"} is like execute with a reconciliation summary;
\code{"rerun"} reproduces a previous run from its \code{manifest.yaml};
pass the manifest path as \code{data} and use a new \code{output_dir}.

Output layout under \code{output_dir}: \code{cleaned-data.csv}
(execute/verify), \code{findings.xlsx} (or \code{findings.csv} without
the \code{writexl} package), \code{audit-log.csv} (execute/verify),
\code{management-report.html}, \code{audit-report.html},
\code{manifest.yaml} (execute/verify), and \code{run-summary.txt}.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    variable: score", "    min: 0", "    max: 100"), rf)
csv <- tempfile(fileext = ".csv")
writeLines(c("sid,score", "S1,90", "S2,150"), csv)
if (requireNamespace("yaml", quietly = TRUE)) {
  cfg <- dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"),
                    id_var = "sid")
  run <- dcc_run(csv, cfg, tempfile("dcc-out"), mode = "preview")
  dcc_run_files(run)
}
}
\seealso{
\code{\link{dcc_config}}, \code{\link{dcc_run_files}},
\code{\link{dcc_doctor}}.
}
