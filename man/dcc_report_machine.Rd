\name{dcc_report_machine}
\alias{dcc_report_machine}
\title{Render the machine report bundle}
\usage{dcc_report_machine(model, output_dir)}
\arguments{
\item{model}{A validated \code{dcc_report_model}.}
\item{output_dir}{Existing or new directory for machine artifacts.}
}
\value{Paths to the eight machine files and the \code{schemas} directory.}
\description{
Writes deterministic JSON and JSONL artifacts, an SHA-256 manifest, and the
versioned schemas an AI agent or external system needs to validate them.
}
