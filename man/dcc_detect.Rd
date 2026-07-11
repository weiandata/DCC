% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/rules.R.
\name{dcc_detect}
\alias{dcc_detect}
\title{Run a rule set against data (Detect stage)}
\usage{
dcc_detect(x, rules, id_var = NULL)
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{rules}{A \code{dcc_ruleset} from \code{\link{dcc_rules}}.}

\item{id_var}{Name of the record-id column, or \code{NULL} for row
numbers.}
}
\value{
A \code{\link{dcc_findings}} table. If \code{x} is a \code{dcc_data},
the result carries a \code{dcc_data} attribute: the input container
with a \code{detect} provenance record (rule file hash, findings count)
appended.
}
\description{
Evaluates every check in a rule set and returns the combined findings
table. Detection is pure and read-only: the same data and the same rule
set always produce the same findings, and the input is never modified.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), score = c(50, 150))
f <- tempfile(fileext = ".yaml")
writeLines(c(
  "checks:",
  "  - id: R001",
  "    type: range",
  "    variable: score",
  "    min: 0",
  "    max: 100"
), f)
if (requireNamespace("yaml", quietly = TRUE)) {
  dcc_detect(df, dcc_rules(f), id_var = "sid")
}
}
