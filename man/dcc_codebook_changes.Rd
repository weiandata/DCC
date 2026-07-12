% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/codebook.R.
\name{dcc_codebook_changes}
\alias{dcc_codebook_changes}
\title{The planned changes of a codebook preview}
\usage{
dcc_codebook_changes(x)
}
\arguments{
\item{x}{A \code{dcc_codebook_preview} from \code{\link{dcc_apply_codebook}}.}
}
\value{
A \code{data.table} of \code{variable}, \code{op}, and \code{detail}.
}
\description{
Returns the table of changes a codebook preview would apply.
}
\examples{
df <- data.frame(sid = "S1", age = -99)
prev <- dcc_apply_codebook(df, list(age = list(missing = -99)))
dcc_codebook_changes(prev)
}
