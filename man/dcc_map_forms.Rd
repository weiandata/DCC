% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/map_forms.R.
\name{dcc_map_forms}
\alias{dcc_map_forms}
\title{Map multi-form responses onto the master item bank}
\usage{
dcc_map_forms(x, form_item_map, form_var)
}
\arguments{
\item{x}{A \code{\link{dcc_data}} object or data.frame of responses.}

\item{form_item_map}{A data.frame with columns \code{form},
\code{source} (item column on that form), \code{master} (master item
bank id) and optionally \code{is_anchor} (logical, default
\code{FALSE}) -- or a path to a CSV file with those columns (hash
recorded in provenance).}

\item{form_var}{Name of the column in \code{x} holding each
respondent's form id.}
}
\value{
A new \code{\link{dcc_data}} version: non-item columns pass through,
consumed source columns are dropped, one column per master item is
appended (\code{NA} where not administered). The normalized item map
(with \code{is_anchor}) is attached as the \code{dcc_item_map}
attribute, mapping findings as the \code{dcc_findings} attribute, and
a \code{map_forms} provenance record is appended.
}
\description{
Aligns item columns from multiple test forms onto the master item bank
using an external form-item mapping table. Items not administered on a
respondent's form are structural \code{NA} -- the
concurrent-calibration layout consumed by the downstream IRTC engine.
Anchor flags are carried through for fixed-anchor equating. Mapping
problems are findings (\code{MAP_SOURCE_MISSING},
\code{MAP_UNKNOWN_FORM}), not silent drops.
}
\examples{
df <- data.frame(sid = c("S1", "S2"), form = c("A", "B"),
                 p1 = c("X", "Y"))
map <- data.frame(form = c("A", "B"), source = c("p1", "p1"),
                  master = c("M001", "M002"))
as.data.frame(dcc_map_forms(df, map, form_var = "form"))
}
