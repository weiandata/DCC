% Hand-maintained until roxygen2 is wired into CI.
\name{dcc_dispositions}
\alias{dcc_dispositions}
\title{Terminal dispositions of a cleaning result}
\usage{
dcc_dispositions(x)
}
\arguments{
\item{x}{A \code{dcc_result} from \code{\link{dcc_execute}}.}
}
\value{
A \code{data.table} with \code{finding_id}, \code{action}, \code{status},
and \code{message}. Status is one of \code{"changed"}, \code{"excluded"},
\code{"flagged"}, \code{"skipped"}, \code{"failed"}, or
\code{"unhandled"}.
}
\description{
Returns one terminal disposition for every finding. Dispositions are the
execution source of truth and are reconciled against the audit log.
}
