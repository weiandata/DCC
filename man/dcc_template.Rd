\name{dcc_template}
\alias{dcc_template}
\title{Create the strict bilingual DCC Excel template}
\usage{dcc_template(path = "DCC-cleaning-plan.xlsx", language = "zh-CN")}
\arguments{
\item{path}{Destination \code{.xlsx} path. Existing files are never overwritten.}
\item{language}{Primary instruction language, \code{"zh-CN"} or \code{"en"};
both languages remain visible in the workbook.}
}
\value{The normalized destination path, invisibly.}
\description{Writes a protected version-1.0 workbook for survey staff. Machine
headers and workbook structure are locked; yellow input cells remain editable.
Sheet protection has no password and prevents accidental edits only.}
