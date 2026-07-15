\name{dcc_help}
\alias{dcc_help}
\title{Explain a DCC workflow code in Chinese or English}
\usage{dcc_help(code = NULL, language = "zh-CN")}
\arguments{
\item{code}{Optional stable issue code. \code{NULL} returns the complete table.}
\item{language}{\code{"zh-CN"} (default) or \code{"en"}.}
}
\value{A data.frame with \code{code}, \code{explanation}, and \code{fix}.}
\description{Returns stable plain-language explanations and suggested fixes for
codes that can appear in strict-plan validation and preflight diagnostics.}
