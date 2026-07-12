% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/config.R.
\name{dcc_read_config}
\alias{dcc_read_config}
\title{Read an Excel cleaning-plan configuration}
\usage{
dcc_read_config(path)
}
\arguments{
\item{path}{Path to the \code{.xlsx} cleaning-plan workbook.}
}
\value{
A \code{dcc_config}.
}
\description{
Converts an Excel cleaning-plan workbook into a \code{\link{dcc_config}},
so survey staff specify the record ID, item columns, rules, and
dispositions in a spreadsheet rather than writing YAML.
}
\details{
The workbook has two sheets. \code{settings} has \code{key}/\code{value}
rows (\code{id_var}, optional \code{items} as a comma-separated list).
\code{rules} has one row per check with columns \code{id}, \code{type},
\code{variable}, \code{min}, \code{max}, \code{values}, \code{items},
\code{max_prop}, \code{max_run}, \code{time_var}, \code{min_seconds},
\code{traps}, \code{severity}, \code{action}, and \code{recode_map}.
Write a starter workbook with \code{\link{dcc_write_config_template}}.
}
\examples{
if (requireNamespace("writexl", quietly = TRUE) &&
    requireNamespace("readxl", quietly = TRUE)) {
  path <- tempfile(fileext = ".xlsx")
  dcc_write_config_template(path)
  dcc_read_config(path)
}
}
\seealso{
\code{\link{dcc_write_config_template}}, \code{\link{dcc_config}},
\code{\link{dcc_run}}.
}
