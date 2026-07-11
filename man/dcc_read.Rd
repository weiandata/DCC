% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/dcc_read.R.
\name{dcc_read}
\alias{dcc_read}
\title{Read a data file into a dcc_data object}
\usage{
dcc_read(path, format = "auto", encoding = "auto", ...)
}
\arguments{
\item{path}{Path to the input file.}

\item{format}{One of \code{"auto"} (default; inferred from the file
extension), \code{"csv"}, \code{"tsv"}, \code{"excel"}, \code{"spss"},
\code{"stata"}, \code{"sas"}, \code{"parquet"}, \code{"feather"},
\code{"json"}.}

\item{encoding}{\code{"auto"} (default) or an explicit source encoding
for text formats (e.g. \code{"UTF-8"}, \code{"GB18030"}, \code{"BIG5"},
\code{"latin1"}). Ignored for binary formats.}

\item{...}{Additional arguments passed to the underlying reader
(\code{data.table::fread}, \code{readxl::read_excel},
\code{haven::read_sav}, ...).}
}
\value{
A \code{\link{dcc_data}} object with \code{meta}, a read report, and a
provenance chain whose first record is the read operation.
}
\description{
The DCC input layer. Reads delimited text (CSV/TSV), Excel, SPSS, Stata,
SAS, Parquet, Feather, and rectangular JSON files into a
\code{\link{dcc_data}} container. Text encodings are auto-detected
(\code{\link{dcc_detect_encoding}}) with explicit override. On read,
level-0 structural diagnostics (\code{\link{dcc_l0_diagnose}}) run
automatically and the resulting read report is attached to the returned
object. Reading never silently coerces: type decisions are recorded in
the read report.
}
\examples{
f <- tempfile(fileext = ".csv")
writeLines(c("id,score", "S1,90", "S2,85"), f)
x <- dcc_read(f)
dcc_read_report(x)
}
