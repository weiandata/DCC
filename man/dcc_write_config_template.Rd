% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/config.R.
\name{dcc_write_config_template}
\alias{dcc_write_config_template}
\title{Write a starter Excel cleaning-plan template}
\usage{
dcc_write_config_template(path)
}
\arguments{
\item{path}{Output \code{.xlsx} path.}
}
\value{
\code{path}, invisibly.
}
\description{
Writes an example two-sheet cleaning-plan workbook that
\code{\link{dcc_read_config}} can read, for survey staff to edit.
}
\examples{
if (requireNamespace("writexl", quietly = TRUE)) {
  dcc_write_config_template(tempfile(fileext = ".xlsx"))
}
}
\seealso{
\code{\link{dcc_read_config}}.
}
