% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/codebook.R.
\name{dcc_apply_codebook}
\alias{dcc_apply_codebook}
\title{Apply a declarative codebook to a dataset}
\usage{
dcc_apply_codebook(x, codebook, dry_run = TRUE)
}
\arguments{
\item{x}{A \code{dcc_data} object or data.frame.}

\item{codebook}{A named list keyed by (current) variable name. Each
entry is a list with any of: \code{rename} (new name), \code{recode} (a
named old -> new value map), \code{missing} (values set to \code{NA}),
\code{type} (target class), \code{label}, \code{value_labels} (a named
vector), and \code{role}.}

\item{dry_run}{If \code{TRUE} (default), return a
\code{dcc_codebook_preview}; if \code{FALSE}, apply and return a new
\code{dcc_data}.}
}
\value{
A \code{dcc_codebook_preview} (dry run) or a new \code{dcc_data}.
}
\description{
Applies a codebook to a dataset: per variable it can rename, recode
values, declare missing codes, coerce type, and attach a label, value
labels, and a role. The preview (\code{dry_run = TRUE}) describes every
change and changes nothing; \code{dry_run = FALSE} returns a new
\code{dcc_data} with a \code{codebook} provenance record. The raw input
is never overwritten, and the preview and apply share one planner, so a
change is previewed exactly as applied. Unknown variables and impossible
type coercions raise \code{dcc_codebook_error}.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), age = c(25, -99),
                 sex = c("1", "2"), stringsAsFactors = FALSE)
cb <- list(
  age = list(missing = -99, type = "integer"),
  sex = list(rename = "gender", recode = c("1" = "M", "2" = "F"),
             label = "Gender")
)
dcc_apply_codebook(df, cb)
dcc_apply_codebook(df, cb, dry_run = FALSE)
}
\seealso{
\code{\link{dcc_codebook_changes}}.
}
