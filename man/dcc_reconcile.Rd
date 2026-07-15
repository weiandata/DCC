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
The findings table extended with the recorded \code{action}, \code{status},
\code{message}, and \code{handled}. Status is one of \code{"changed"},
\code{"excluded"}, \code{"flagged"}, \code{"skipped"}, \code{"failed"},
or \code{"unhandled"}.
}
\description{
Verifies DCC's closed-loop guarantee on the exact finding identity:
every audit-log row must join back to a finding by \code{finding_id},
and every finding is assigned exactly one terminal \code{status}. There
is no loose \code{record_id + check_id} matching, so a change can never
be attributed to the wrong finding and an unhandled finding can never
be reported as handled. An audit row whose \code{finding_id} is absent
from the findings table, or a handled disposition without matching audit
evidence, raises a \code{dcc_reconcile_error}.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C",
                  evidence = "legacy code")
res <- dcc_execute(df, f, actions = list(C = "set_na"), id_var = "sid")
dcc_reconcile(res)
}
