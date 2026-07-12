% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/report.R.
\name{dcc_report}
\alias{dcc_report}
\title{Generate a cleaning report (Report stage)}
\usage{
dcc_report(x, path = NULL, audience = c("summary", "audit"),
  max_rows = 1000L)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}

\item{path}{Output \code{.html} file path, or \code{NULL} to only
return the HTML string.}

\item{audience}{\code{"summary"} (management layer, default) or
\code{"audit"} (adds findings-to-changes reconciliation and the
cell-level change log).}

\item{max_rows}{Maximum audit-log rows embedded in the HTML (default
1000); the complete log is exported with
\code{\link{dcc_export_log}}.}
}
\value{
The HTML document as a character string, invisibly. Written to
\code{path} when given.
}
\description{
Renders a self-contained HTML report in two audiences: a management
summary (findings by quality dimension and severity, change volumes,
exclusions, provenance and hashes) and an audit report that adds the
reconciliation table and the cell-level change log. HTML is generated
directly, without a pandoc/rmarkdown dependency.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), score = c(50, 150))
f <- dcc_findings("S2", variable = "score", check_id = "R001",
                  evidence = "out of range", severity = "fail",
                  dimension = "validity")
res <- dcc_execute(df, f, actions = list(R001 = "set_na"),
                   id_var = "sid")
html <- dcc_report(res, audience = "audit")
substr(html, 1, 60)
}
