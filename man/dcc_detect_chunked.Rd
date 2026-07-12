% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/chunked.R.
\name{dcc_detect_chunked}
\alias{dcc_detect_chunked}
\title{Run record-local checks over a file in chunks}
\usage{
dcc_detect_chunked(path, rules, chunk_size = 100000L, id_var = NULL,
  sep = ",", backend = c("auto", "csv", "arrow"), encoding = "auto")
}
\arguments{
\item{path}{Path to the input file: a delimited text file (CSV/TSV)
for the \code{csv} backend, or a Parquet/Feather file for the
\code{arrow} backend.}

\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{chunk_size}{Rows per chunk / record batch (default 100000).}

\item{id_var}{Name of the record-id column, or \code{NULL} to use
global row numbers (consistent across chunks).}

\item{sep}{Field separator for the \code{csv} backend (default
\code{","}); ignored by the \code{arrow} backend.}

\item{backend}{One of \code{"auto"} (default), \code{"csv"}, or
\code{"arrow"}.}

\item{encoding}{Encoding of the \code{csv} backend input:
\code{"auto"} (default, auto-detected) or an explicit name such as
\code{"UTF-8"} or \code{"latin1"}. Pass one explicitly when
auto-detection misfires on pure-ASCII or low-signal data. Ignored by
the \code{arrow} backend.}
}
\value{
A \code{\link{dcc_findings}} table with \code{n_rows} (total rows
scanned), \code{n_chunks}, and \code{backend} attributes.
}
\description{
Larger-than-memory detection with an adaptive backend: chunks (or
Arrow record batches) of \code{chunk_size} rows are read and checked
one at a time, so peak memory is bounded by the chunk. Findings are
identical to an in-memory \code{\link{dcc_detect}} for record-local
checks (\code{range}, \code{set}, \code{missing_items},
\code{straightlining}, \code{trap_items}, and \code{response_time}
with the median-relative cut disabled via \code{min_median_ratio: ~}).
Cross-record checks (\code{score_anomaly}, median-relative response
time) are rejected with typed errors; \code{expr} rules must not use
aggregate functions.
}
\details{
Two backends share this entry point and produce identical findings:
the \code{csv} backend streams a delimited file with
\code{\link[data.table]{fread}} (fread-native \code{UTF-8}/\code{latin1}
encoding only; column types are locked from the first chunk so later
chunks cannot drift), and the \code{arrow} backend streams a
Parquet/Feather file as record batches (requires the \code{arrow}
package; types come from the file schema and the columnar format is
always \code{UTF-8}, so the encoding restriction does not apply). With
\code{backend = "auto"} the backend is chosen from the file extension:
\code{arrow} for \code{.parquet}/\code{.feather}, \code{csv} for
\code{.csv}/\code{.tsv}/\code{.txt}.
}
\seealso{
\code{\link{dcc_detect}} for in-memory detection.
}
