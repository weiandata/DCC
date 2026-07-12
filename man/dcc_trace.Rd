% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/report.R.
\name{dcc_trace}
\alias{dcc_trace}
\title{Trace the cleaning history of a record or cell}
\usage{
dcc_trace(x, record_id, variable = NULL)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}

\item{record_id}{Record identifier (as used in the findings).}

\item{variable}{Optional variable name to narrow the trace to a single
cell.}
}
\value{
A \code{dcc_trace} object: list with \code{record_id},
\code{variable}, \code{findings} (matching findings rows) and
\code{changes} (matching audit rows).
}
\description{
Reverse lookup from the cleaned data back through the pipeline: all
findings and all logged changes for one record, optionally narrowed to
one cell. This implements the auditable-reporting requirement that any
cell in the final dataset can be traced to its cleaning history.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C",
                  evidence = "legacy code")
res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
dcc_trace(res, "S1", "q1")
}
