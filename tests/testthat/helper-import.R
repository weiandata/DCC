strict_import_spec <- function(path, columns = NULL, missing = NULL) {
  if (is.null(columns)) {
    columns <- data.frame(
      source_name = c("编号", "年龄", "性别"),
      name = c("sid", "age", "gender"),
      type = c("character", "integer", "character"),
      role = c("id", "demographic", "demographic"),
      stringsAsFactors = FALSE
    )
  }
  if (is.null(missing)) {
    missing <- data.frame(
      variable = "age",
      source_value = "-99",
      state = "declared_missing_code",
      stringsAsFactors = FALSE
    )
  }
  new_import_spec(
    path, "csv", options = list(encoding = "UTF-8"),
    columns = columns, missing = missing
  )
}
