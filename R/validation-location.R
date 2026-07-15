plan_source_info <- function(x) {
  attr(x, "dcc_plan_source", exact = TRUE)
}
json_pointer_escape <- function(x) {
  x <- gsub("~", "~0", x, fixed = TRUE)
  gsub("/", "~1", x, fixed = TRUE)
}

validation_json_pointer <- function(field, rows) {
  parts <- strsplit(field, ".", fixed = TRUE)[[1L]]
  parts <- vapply(parts, json_pointer_escape, character(1))
  if (length(rows) && length(parts) >= 2L) {
    parts <- c(parts[1L], as.character(rows[1L] - 1L), parts[-1L])
  }
  paste0("/", paste(parts, collapse = "/"))
}

locate_plan_validation <- function(validation, plan) {
  source <- plan_source_info(plan)
  if (is.null(source) || !nrow(validation)) return(validation)
  if (identical(source$type, "json")) {
    for (i in seq_len(nrow(validation))) {
      validation$field[i] <- validation_json_pointer(
        validation$field[i], validation$rows[[i]]
      )
    }
    return(validation[])
  }
  if (!identical(source$type, "xlsx")) return(validation)

  validation$workbook <- rep(source$path, nrow(validation))
  locations <- source$locations
  for (i in seq_len(nrow(validation))) {
    candidates <- locations[locations$field == validation$field[i], ]
    issue_rows <- validation$rows[[i]]
    if (length(issue_rows) && nrow(candidates)) {
      candidates <- candidates[candidates$index == issue_rows[1L], ]
    }
    if (!nrow(candidates)) next
    location <- candidates[1L, ]
    validation$sheet[i] <- location$sheet
    validation$row[i] <- location$row
    validation$column[i] <- location$column
    validation$cell[i] <- location$cell
  }
  validation[]
}
