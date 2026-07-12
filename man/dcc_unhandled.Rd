% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/accessors.R.
\name{dcc_unhandled}
\alias{dcc_unhandled}
\title{Findings left unhandled by execution}
\usage{
dcc_unhandled(x)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}
}
\value{
A \code{\link{dcc_findings}} table (possibly empty) of findings that had
no explicit action and were therefore neither changed nor
dispositioned.
}
\description{
Returns the findings that had no explicit action in
\code{\link{dcc_execute}}. This is the public accessor for the result's
unhandled set; callers should not read the underlying list element
directly.
}
\examples{
df <- data.frame(sid = "S1", q1 = 9)
f <- dcc_findings("S1", variable = "q1", check_id = "C", evidence = "e")
res <- dcc_execute(df, f, actions = list(), id_var = "sid")
dcc_unhandled(res)
}
