% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/execute.R.
\name{dcc_audit_log}
\alias{dcc_audit_log}
\alias{dcc_cleaned}
\title{Accessors for dcc_result objects}
\usage{
dcc_audit_log(x)

dcc_cleaned(x)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}
}
\value{
\code{dcc_audit_log} returns the cell-level audit log
(\code{data.table} with columns \code{record_id}, \code{variable},
\code{old_value}, \code{new_value}, \code{action}, \code{check_id},
\code{method}, \code{timestamp}, \code{dcc_version},
\code{ruleset_hash}, \code{keyfile_hash}). \code{dcc_cleaned} returns
the new \code{\link{dcc_data}} version.
}
\description{
Access the machine-readable audit log and the cleaned dataset produced
by the Execute stage. The audit log is the backbone of DCC's
auditable-reporting guarantee: every row records one change traceable
to one finding.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C",
                  evidence = "legacy code")
res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
dcc_audit_log(res)
dcc_cleaned(res)
}
