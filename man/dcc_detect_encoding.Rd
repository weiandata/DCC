% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/encoding.R.
\name{dcc_detect_encoding}
\alias{dcc_detect_encoding}
\title{Detect the character encoding of a text file}
\usage{
dcc_detect_encoding(path, n_bytes = 65536L)
}
\arguments{
\item{path}{Path to the file.}

\item{n_bytes}{Maximum number of bytes to sample (default 65536).}
}
\value{
A list with elements \code{encoding} (normalized name),
\code{confidence} (0-1), and \code{candidates} (data.frame of raw
detector output).
}
\description{
Reads up to \code{n_bytes} from the file and detects the most likely
character encoding via \code{stringi::stri_enc_detect()}. Detected
encodings are normalized to the canonical names DCC supports as
first-class: \code{"UTF-8"}, \code{"GB18030"} (covers GBK/GB2312),
\code{"BIG5"}, and \code{"latin1"} (covers ISO-8859-1/windows-1252).
}
\examples{
f <- tempfile(fileext = ".csv")
writeLines("id,name", f)
dcc_detect_encoding(f)$encoding
}
