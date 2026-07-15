% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/dcc_read.R.
\name{dcc_read}
\alias{dcc_read}
\title{Read a data file into a dcc_data object}
\usage{
dcc_read(path, format = "auto", encoding = "auto", ...)
}
\arguments{
\item{path}{Path to the input file.}

\item{format}{\code{"auto"}, a registered format name, or the legacy
\code{"excel"} alias for XLS/XLSX. Ambiguous extensions require an explicit
format.}

\item{encoding}{\code{"auto"} (default) or an explicit source encoding
for text formats (e.g. \code{"UTF-8"}, \code{"GB18030"}, \code{"BIG5"},
\code{"latin1"}). Ignored for binary formats.}

\item{...}{Compatibility reader options. Strict protected options remain
rejected by the adapter.}
}
\value{
A \code{\link{dcc_data}} object with \code{meta}, a read report, and a
provenance chain whose first record is the read operation.
}
\description{
Compatibility entry point over DCC's registered format adapters. New strict
workflows use \code{\link{dcc_import}} with a declared import specification;
this function retains automatic text-encoding detection and type inference for
existing calls. The raw file is never modified.
}
\examples{
f <- tempfile(fileext = ".csv")
writeLines(c("id,score", "S1,90", "S2,85"), f)
x <- dcc_read(f)
dcc_read_report(x)
}
