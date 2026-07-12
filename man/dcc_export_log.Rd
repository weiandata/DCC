% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/execute.R.
\name{dcc_export_log}
\alias{dcc_export_log}
\title{Export an audit log for external auditors}
\usage{
dcc_export_log(x, path, format = c("parquet", "csv"))
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}

\item{path}{Output file path.}

\item{format}{\code{"parquet"} (default; schema-typed and compact,
requires the \pkg{arrow} package) or \code{"csv"} (plain file for
auditors without Parquet tooling).}
}
\value{
\code{path}, invisibly.
}
\description{
Writes the cell-level audit log to disk. Parquet is the default
storage format (design decision 3 in \code{docs/design.md}); CSV
export exists so external auditors can open the log without special
tooling.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C",
                  evidence = "legacy code")
res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
csv <- tempfile(fileext = ".csv")
dcc_export_log(res, csv, format = "csv")
}
