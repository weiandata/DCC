% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/validate.R.
\name{dcc_validation_errors}
\alias{dcc_validation_errors}
\title{The failing issues of a validation report}
\usage{
dcc_validation_errors(x)
}
\arguments{
\item{x}{A \code{dcc_validation} object.}
}
\value{
The subset of \code{x} with \code{severity == "fail"}.
}
\description{
Filters a validation report to only the blocking (\code{"fail"}) issues.
}
\examples{
df <- data.frame(sid = c("S1", "S1"), score = c(50, 70))
dcc_validation_errors(dcc_validate_data(df, id_var = "sid"))
}
