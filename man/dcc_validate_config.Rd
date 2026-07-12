% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/run.R.
\name{dcc_validate_config}
\alias{dcc_validate_config}
\title{Validate a cleaning configuration}
\usage{
dcc_validate_config(config)
}
\arguments{
\item{config}{A \code{dcc_config} from \code{\link{dcc_config}}.}
}
\value{
A \code{dcc_validation} object.
}
\description{
Runs \code{\link{dcc_validate_rules}} over the config's rules and
additionally checks that every action targets a \code{check_id} the
rules can produce.
}
\examples{
rf <- tempfile(fileext = ".yaml")
writeLines(c("checks:", "  - id: R001", "    type: range",
             "    variable: score", "    min: 0", "    max: 100"), rf)
if (requireNamespace("yaml", quietly = TRUE)) {
  cfg <- dcc_config(dcc_rules(rf), actions = list(R001 = "set_na"))
  dcc_validate_config(cfg)
}
}
