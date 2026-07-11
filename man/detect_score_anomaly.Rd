% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/detectors.R.
\name{detect_score_anomaly}
\alias{detect_score_anomaly}
\title{Detect group-wise score anomalies}
\usage{
detect_score_anomaly(x, score_var, group_vars = NULL,
  method = c("iqr", "zscore"), k = 1.5, group_mean_z = 2,
  id_var = NULL, severity = "warn")
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{score_var}{Name of the numeric score column.}

\item{group_vars}{Character vector of grouping columns; \code{NULL}
treats the data as one group.}

\item{method}{\code{"iqr"} (default) or \code{"zscore"} for
within-group outliers.}

\item{k}{Fence multiplier: IQR multiplier (default 1.5) or |z| cutoff
(use e.g. 3 with \code{method = "zscore"}).}

\item{group_mean_z}{Flag groups whose mean is more than this many
overall standard deviations from the overall mean (default 2;
\code{NULL} skips the group-level check).}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}

\item{severity}{Severity assigned to findings (default \code{"warn"}).}
}
\value{
A \code{\link{dcc_findings}} table (check ids \code{Q_SCORE_OUTLIER}
and \code{Q_GROUP_SCORE_SHIFT}; group-level findings have
\code{record_id = NA} and the group label in \code{evidence}).
}
\description{
Flags respondents whose score is an outlier within their group (IQR
fences or z-scores), and groups whose mean deviates strongly from the
overall mean.
}
\examples{
df <- data.frame(sid = sprintf("S\%d", 1:8),
                 grp = rep(c("A", "B"), each = 4),
                 score = c(80, 82, 15, 81, 60, 62, 61, 59))
detect_score_anomaly(df, "score", group_vars = "grp", id_var = "sid")
}
