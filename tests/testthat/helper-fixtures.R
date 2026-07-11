# Synthetic fixtures only (repository policy: no real client data).

# A small survey-like table with Chinese labels for encoding tests.
fixture_df <- function() {
  data.frame(
    student_id = c("S001", "S002", "S003"),
    school = c("北京一中", "上海实验",
               "广州中学"), # 北京一中 / 上海实验 / 广州中学
    q1 = c(1L, 2L, NA_integer_),
    q2 = c("A", "B", "C"),
    score = c(85.5, 90.0, 77.25),
    stringsAsFactors = FALSE
  )
}

# Write fixture_df() as a delimited file in a given encoding.
write_fixture_csv <- function(path, encoding = "UTF-8", sep = ",") {
  df <- fixture_df()
  lines <- c(
    paste(names(df), collapse = sep),
    vapply(seq_len(nrow(df)), function(i) {
      row <- vapply(df[i, ], function(v) {
        if (is.na(v)) "" else as.character(v)
      }, character(1))
      paste(row, collapse = sep)
    }, character(1))
  )
  txt <- paste0(paste(lines, collapse = "\n"), "\n")
  raw <- stringi::stri_conv(txt, from = "UTF-8", to = encoding,
                            to_raw = TRUE)[[1]]
  writeBin(raw, path)
  invisible(path)
}
