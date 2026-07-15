\name{dcc_check}
\alias{dcc_check}
\title{Check a strict DCC project without changing data}
\usage{dcc_check(data, plan, output_dir = "dcc-check")}
\arguments{
\item{data}{Existing source data file path.}
\item{plan}{Strict \code{.xlsx}/\code{.json} plan path or a \code{dcc_plan}.}
\item{output_dir}{New directory for check diagnostics.}
}
\value{A \code{dcc_check_result} with status, validation, findings, imported
data, and written files.}
\description{Validates the plan, performs a strict canonical import, runs
environment and data checks, and previews findings. It writes diagnostics and a
bilingual staff report only; no action, cleaned dataset, audit log, or manifest
is produced.}
