\name{dcc_read_plan}
\alias{dcc_read_plan}
\title{Read a strict DCC Excel or JSON plan}
\usage{dcc_read_plan(path)}
\arguments{\item{path}{Existing \code{.xlsx} or \code{.json} plan path.}}
\value{A \code{dcc_plan}. Excel plans retain cell-location metadata used by
\code{dcc_validate_plan()}; JSON validation uses JSON Pointers.}
\description{Reads only the exact version-1.0 contract. Unknown, missing,
reordered, or renamed workbook sheets and columns are rejected instead of
guessed.}
