\name{dcc_validate_json}
\alias{dcc_validate_json}
\alias{dcc_validate_jsonl}
\title{Validate DCC JSON and JSON Lines artifacts}
\usage{
dcc_validate_json(path, schema)

dcc_validate_jsonl(path, schema)
}
\arguments{
\item{path}{Existing JSON or JSON Lines file.}
\item{schema}{A schema name accepted by \code{dcc_schema()}.}
}
\value{\code{TRUE} when the artifact matches the published contract.}
\description{
Uses DCC's built-in structural validator, avoiding an additional runtime
dependency. Published schema files remain compatible with full external JSON
Schema validators.
}
