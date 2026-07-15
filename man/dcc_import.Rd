\name{dcc_import}
\alias{dcc_import}
\title{Strict canonical import}
\usage{
dcc_import(path, spec)
}
\arguments{
\item{path}{Path to the source file.}

\item{spec}{A \code{dcc_import_spec} created internally from a strict DCC
plan.}
}
\value{
A \code{dcc_data} object with canonical data, dictionary, missing states,
import specification, source metadata, and import provenance.
}
\description{
Reads a source through its registered format adapter and applies an explicit
import specification. Source names, canonical names, types, missing codes, and
roles are declared rather than guessed. The source file is never modified.
}
