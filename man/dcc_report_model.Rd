\name{dcc_report_model}
\alias{dcc_report_model}
\alias{dcc_validate_report_model}
\title{Build and validate the normalized report model}
\usage{
dcc_report_model(result, run = NULL)

dcc_validate_report_model(x)
}
\arguments{
\item{result}{A \code{dcc_result} returned by \code{dcc_execute()}.}
\item{run}{An optional \code{dcc_run} containing run and plan metadata.}
\item{x}{A report-model-like named list to validate.}
}
\value{
\code{dcc_report_model()} returns a versioned \code{dcc_report_model} list.
\code{dcc_validate_report_model()} returns a structured
\code{dcc_validation} table with stable error codes.
}
\description{
Creates the single normalized source of facts consumed by staff,
statistical, and machine report renderers. The constructor copies source
objects and verifies counts, finding identities, hashes, and timings.
}
