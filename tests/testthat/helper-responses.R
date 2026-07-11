# Synthetic response data for detector tests (repository policy: no
# real client data). 8 respondents, 10 Likert items, plus metadata.
fixture_responses <- function() {
  df <- data.frame(
    sid = sprintf("S%03d", 1:8),
    grp = c("A", "A", "A", "A", "B", "B", "B", "B"),
    time_total = c(600, 580, 40, 610, 590, 620, 605, 200),
    trap1 = c(3, 3, 1, 3, 3, 3, 5, 3), # expected 3
    score = c(80, 82, 15, 81, 60, 62, 61, 59),
    stringsAsFactors = FALSE
  )
  items <- matrix(
    c(
      1, 2, 3, 2, 1, 4, 5, 2, 3, 1,  # S001 normal
      2, 3, 2, 4, 5, 1, 2, 3, 4, 5,  # S002 normal
      4, 4, 4, 4, 4, 4, 4, 4, 4, 4,  # S003 straight-liner
      1, NA, 2, NA, 3, NA, 1, 2, 4, 5, # S004 some missing
      NA, NA, NA, NA, NA, NA, NA, 1, 2, 3, # S005 70% missing
      5, 4, 3, 2, 1, 5, 4, 3, 2, 1,  # S006 normal
      1, 1, 1, 2, 2, 2, 3, 3, 3, 4,  # S007 short runs only
      2, 2, 2, 2, 2, 3, 4, 5, 1, 2   # S008 run of 5
    ),
    nrow = 8, byrow = TRUE
  )
  colnames(items) <- paste0("q", 1:10)
  cbind(df, as.data.frame(items))
}

item_names <- function() paste0("q", 1:10)
