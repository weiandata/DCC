\name{dcc_result_summary}
\alias{dcc_result_summary}
\title{Create a structured AI summary of a DCC result}
\usage{dcc_result_summary(result, detail = c("compact", "full"))}
\arguments{
\item{result}{A \code{dcc_result} returned by \code{dcc_execute()}.}
\item{detail}{\code{"compact"} returns at most 20 finding rows without raw
evidence; \code{"full"} adds reconciliation, provenance, and hashes.}
}
\value{A named structured list containing stable action codes.}
\description{
Returns bounded, deterministic fields for AI agents without requiring them to
parse console prose or hidden R attributes.
}
