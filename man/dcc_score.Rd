% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/score.R.
\name{dcc_score}
\alias{dcc_score}
\title{Score responses against an answer key}
\usage{
dcc_score(x, answer_key, omit_policy = c("zero", "na"),
  scoring_fn = NULL)
}
\arguments{
\item{x}{A \code{\link{dcc_data}} object or data.frame of responses.}

\item{answer_key}{A data.frame with columns \code{item}, \code{key},
and optionally \code{type} (\code{"single"}/\code{"multiple"}, default
\code{"single"}), \code{points} (default 1), \code{partial} (default
\code{FALSE}) -- or a path to a CSV file with those columns (the
file's MD5 hash is recorded in the provenance chain).}

\item{omit_policy}{\code{"zero"} (omitted item scores 0, default) or
\code{"na"} (omitted stays \code{NA}; use after
\code{\link{dcc_map_forms}} so not-administered items are not scored
as wrong).}

\item{scoring_fn}{Optional \code{function(responses, key_row)}
returning a numeric vector with exactly one value per response; replaces
built-in scoring for every item.
This is the extension point reserved for weighted/rubric/polytomous
scoring (design decision 2).}
}
\value{
A new \code{\link{dcc_data}} version with one \code{<item>_score}
column per keyed item and a \code{total_score} column appended, plus a
\code{score} provenance record (key source, key hash, omit policy).
}
\description{
Scores responses using an external, versioned answer key. Single-choice
items get full points on exact match. Multiple-select items (responses
like \code{"AC"} or \code{"A,C"}) are all-or-nothing by default; with
\code{partial = TRUE} the score is
\code{points * max(0, (hits - false_alarms) / n_key)}.
When \code{omit_policy = "na"}, a row with no observed item scores has an
\code{NA} total rather than zero.
}
\examples{
df <- data.frame(sid = c("S1", "S2"),
                 it1 = c("A", "B"), it2 = c("AC", "A"))
key <- data.frame(item = c("it1", "it2"), key = c("A", "AC"),
                  type = c("single", "multiple"))
as.data.frame(dcc_score(df, key))
}
