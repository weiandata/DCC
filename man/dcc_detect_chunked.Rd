% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/chunked.R.
\name{dcc_detect_chunked}
\alias{dcc_detect_chunked}
\title{Run record-local checks over a file in chunks}
\usage{
dcc_detect_chunked(path, rules, chunk_size = 100000L, id_var = NULL,
  sep = ",")
}
\arguments{
\item{path}{Path to a delimited text file (CSV/TSV) in an
fread-native encoding (UTF-8/latin1); convert other encodings once via
\code{\link{dcc_read}} + export first.}

\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{chunk_size}{Rows per chunk (default 100000).}

\item{id_var}{Name of the record-id column, or \code{NULL} to use
global row numbers (consistent across chunks).}

\item{sep}{Field separator (default \code{","}).}
}
\value{
A \code{\link{dcc_findings}} table with \code{n_rows} (total rows
scanned) and \code{n_chunks} attributes.
}
\description{
Larger-than-memory detection for delimited files: chunks of
\code{chunk_size} rows are read and checked one at a time, so peak
memory is bounded by the chunk. Findings are identical to an in-memory
\code{\link{dcc_detect}} for record-local checks (\code{range},
\code{set}, \code{missing_items}, \code{straightlining},
\code{trap_items}, and \code{response_time} with the median-relative
cut disabled via \code{min_median_ratio: ~}). Cross-record checks
(\code{score_anomaly}, median-relative response time) are rejected
with typed errors; \code{expr} rules must not use aggregate functions.
Column types are locked from the first chunk so later chunks cannot
drift.
}
\seealso{
\code{\link{dcc_detect}} for in-memory detection.
}
