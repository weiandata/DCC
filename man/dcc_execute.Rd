% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/execute.R.
\name{dcc_execute}
\alias{dcc_execute}
\title{Execute actions on detected findings (Execute stage)}
\usage{
dcc_execute(x, findings, actions = list(), id_var = NULL,
  default = "flag", ruleset_hash = NULL)
}
\arguments{
\item{x}{A \code{\link{dcc_data}} object or data.frame.}

\item{findings}{A \code{\link{dcc_findings}} table from the Detect
stage with unique, non-empty \code{finding_id} values.}

\item{actions}{Named list mapping \code{check_id}s to actions:
\code{"exclude"}, \code{"set_na"}, \code{"flag"}, or
\code{list(action = "recode", map = c(old = new))}. Every name must
match a \code{check_id} in \code{findings}; unknown action IDs are an
error.}

\item{id_var}{Name of the record-id column matching the findings'
\code{record_id}, or \code{NULL} for row numbers. When supplied, the
column must contain non-missing, unique ids.}

\item{default}{Deprecated and no longer applied: findings without an
explicit action are returned unhandled rather than auto-dispositioned.
Retained only for call compatibility.}

\item{ruleset_hash}{Optional rule-file hash stamped into the audit log
(taken from the findings' \code{dcc_data} attribute when available).}
}
\value{
A \code{dcc_result}: list with \code{data} (the new
\code{\link{dcc_data}} version), \code{audit} (cell-level audit log
whose first column is \code{finding_id}), \code{unhandled} (findings
with no explicit action), and \code{n_excluded}. Accessors:
\code{\link{dcc_audit_log}}, \code{\link{dcc_cleaned}}.
}
\description{
Applies declarative actions to detected findings under the closed-loop
rule: only cells and records named in the findings list are ever
touched, and every change is logged at cell level (old value, new
value, triggering check, method, timestamps, versions) carrying the
exact \code{finding_id} that produced it. The whole plan is validated
before any data changes -- unknown action IDs, unmapped recodes,
missing or duplicated record ids, and group-level cell actions are
errors. Findings without a mapped action are returned \code{unhandled}
rather than silently flagged or dropped. The input is never modified.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), score = c(50, 150))
f <- dcc_findings("S2", variable = "score", check_id = "R001",
                  evidence = "out of range", severity = "fail")
res <- dcc_execute(df, f, actions = list(R001 = "set_na"),
                   id_var = "sid")
dcc_audit_log(res)
}
