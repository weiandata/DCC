% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/capabilities.R.
\name{dcc_capabilities}
\alias{dcc_capabilities}
\title{Machine-readable DCC capability document}
\usage{
dcc_capabilities()
}
\value{
A named list with \code{contract_version} (the capability-contract
version), \code{package_version} (the installed DCC version),
\code{features} (a data.frame of \code{name}, \code{status} --
\code{"Stable"}/\code{"Experimental"}/\code{"Planned"} -- and
\code{since}), \code{rule_types}, \code{action_types}, \code{formats}
(a data.frame of \code{format} and its \code{reader}), and
\code{unsupported} (operations DCC does not perform).
}
\description{
Returns a versioned, deterministic description of every public
capability, rule type, action type, and input format, plus the
operations DCC deliberately does not support. General-purpose callers
(including AI systems) can query it to discover what is Stable,
Experimental, or Planned before building a pipeline. The \code{status}
of each feature reflects the implemented state of the installed
package, not a roadmap.
}
\examples{
caps <- dcc_capabilities()
caps$action_types
caps$features[caps$features$status == "Stable", "name"]
}
\seealso{
\code{\link{dcc_schema}} for the formal object schemas.
}
