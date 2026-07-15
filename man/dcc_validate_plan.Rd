\name{dcc_validate_plan}
\alias{dcc_validate_plan}
\title{Validate a strict DCC project plan}
\usage{dcc_validate_plan(x)}
\arguments{\item{x}{A \code{dcc_plan}, normally returned by
\code{dcc_read_plan()}.}}
\value{A \code{dcc_validation} table. Blocking rows have severity
\code{"fail"}.}
\description{Validates the common versioned contract used by strict Excel
workbooks and JSON plans. Validation is read-only and returns stable issue
codes suitable for staff help pages and AI agents.}
