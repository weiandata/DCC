% Hand-maintained until roxygen2 is wired into CI; keep in sync with R/accessors.R.
\name{dcc_item_map}
\alias{dcc_item_map}
\title{Master item map of a form-mapped dataset}
\usage{
dcc_item_map(x)
}
\arguments{
\item{x}{A \code{dcc_data} returned by \code{\link{dcc_map_forms}}.}
}
\value{
The item-map \code{data.frame} (\code{master}, \code{form},
\code{source}, \code{is_anchor}, ...).
}
\description{
Returns the resolved form-to-master item map attached by
\code{\link{dcc_map_forms}}. This is the public accessor for the
mapping; callers should not read the hidden attribute directly.
}
\examples{
data <- data.frame(sid = c("S1", "S2"), form = c("A", "B"),
                   p1 = c(1, 2), p2 = c(5, 6))
fmap <- data.frame(form = c("A", "A", "B", "B"),
                   source = c("p1", "p2", "p1", "p2"),
                   master = c("M001", "M002", "M003", "M002"),
                   is_anchor = c(FALSE, TRUE, FALSE, TRUE))
mapped <- dcc_map_forms(data, fmap, form_var = "form")
dcc_item_map(mapped)
}
