\name{dcc_report_staff}
\alias{dcc_report_staff}
\title{Render the bilingual staff report}
\usage{
dcc_report_staff(
  model,
  output_dir,
  formats = c("xlsx", "html"),
  language = c("zh-CN", "en"),
  include_examples = FALSE
)
}
\arguments{
\item{model}{A validated \code{dcc_report_model}.}
\item{output_dir}{Existing or new directory for the report files.}
\item{formats}{Any combination of \code{"xlsx"} and \code{"html"}.}
\item{language}{Primary display language, \code{"zh-CN"} or \code{"en"}.}
\item{include_examples}{Whether raw examples may be disclosed. Defaults to
\code{FALSE}.}
}
\value{Character paths of files written, including \code{run-summary.txt}.}
\description{
Produces the staff workbook, dependency-free HTML report, and concise text
summary from one normalized model. Sensitive examples are masked by default,
and Excel row limits are checked before writing so data are never truncated.
}
