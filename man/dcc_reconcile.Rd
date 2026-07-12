% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/report.R.
\name{dcc_reconcile}
\alias{dcc_reconcile}
\title{Reconcile findings against logged changes (closed loop)}
\usage{
dcc_reconcile(x)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}
}
\value{
The findings table extended with \code{action} (the executed action,
\code{NA} if none) and \code{handled} (logical). The number of audit
rows that do not match any finding is attached as the
\code{unreconciled_changes} attribute (must be 0 in a healthy
pipeline).
}
\description{
Verifies DCC's closed-loop guarantee from both directions: every
finding should have at least one audit-log row, and every audit-log
row must trace back to a finding -- a change without a detected
violation is a pipeline violation.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C",
                  evidence = "legacy code")
res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
dcc_reconcile(res)
}
