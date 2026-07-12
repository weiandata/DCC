% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/rules.R.
\name{dcc_rules}
\alias{dcc_rules}
\title{Load a declarative rule set from a YAML file}
\usage{
dcc_rules(path)
}
\arguments{
\item{path}{Path to the YAML rule file.}
}
\value{
A \code{dcc_ruleset} object (list of normalized rules, with the source
file and its MD5 hash attached for the audit trail).
}
\description{
Rule files are YAML with embedded R expressions for complex logic. The
top-level key \code{checks} holds a list of rules; each rule has
\code{id}, \code{type}, an optional \code{severity} and
\code{dimension}, and type-specific fields: \code{range}
(\code{variable}, \code{min}/\code{max}), \code{set} (\code{variable},
\code{values}), \code{expr} (an R expression evaluated per record in a
restricted environment), \code{skip_logic} (\code{when}
\{\code{variable}, \code{equals}\} and \code{then_not_required}, marking
skipped items as not administered for the missing-items detector), or a
detector type (\code{missing_items}, \code{straightlining},
\code{response_time}, \code{trap_items}, \code{score_anomaly}) whose
fields are passed to the matching \code{detect_*()} function.
}
\examples{
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
  dcc_rules(f)
}
}
