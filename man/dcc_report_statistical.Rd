\name{dcc_report_statistical}
\alias{dcc_report_statistical}
\title{Render the statistical report bundle}
\usage{
dcc_report_statistical(
  model,
  output_dir,
  table_format = c("parquet", "csv"),
  html = TRUE
)
}
\arguments{
\item{model}{A validated \code{dcc_report_model}.}
\item{output_dir}{Existing or new directory for report files.}
\item{table_format}{Complete tables as \code{"parquet"} or \code{"csv"}.}
\item{html}{Whether to write the statistical HTML narrative.}
}
\value{Character paths of every file written.}
\description{
Writes complete findings, audit, reconciliation, before/after profiles,
scoring, mapping, provenance, parameters, and an optional methods narrative.
The artifact manifest records SHA-256 hashes after every artifact is closed.
}
