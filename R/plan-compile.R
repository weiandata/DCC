plan_source_option_names <- function(format) {
  common <- c("member", "compression", "max_uncompressed_bytes")
  switch(
    format,
    csv = c("encoding", common),
    tsv = c("encoding", common),
    txt = c("encoding", "delimiter", common),
    fwf = c("encoding", "widths", "col_names", common),
    json = c("encoding", common),
    jsonl = c("encoding", common),
    xls = c("sheet", "range", common),
    xlsx = c("sheet", "range", common),
    xlsb = c("sheet", "range", common),
    ods = c("sheet", "range", common),
    spss = c("encoding", common),
    stata = common,
    sas = c("encoding", "catalog_file", "catalog_encoding", common),
    xpt = common,
    parquet = common,
    feather = common,
    rds = common,
    character()
  )
}

plan_option_value <- function(name, value) {
  value <- as.character(value)
  if (name == "sheet" && grepl("^[0-9]+$", value)) return(as.integer(value))
  if (name == "max_uncompressed_bytes") return(as.numeric(value))
  if (name == "widths") {
    return(as.numeric(trimws(strsplit(value, ",", fixed = TRUE)[[1L]])))
  }
  if (name == "col_names") {
    return(trimws(strsplit(value, ",", fixed = TRUE)[[1L]]))
  }
  value
}

plan_import_options <- function(plan) {
  source <- plan$source
  format <- tolower(as.character(source$format))
  json <- as.character(source$options_json %||% "")
  options <- if (nzchar(json)) {
    jsonlite::fromJSON(json, simplifyVector = TRUE)
  } else {
    list()
  }
  if (!is.list(options)) {
    dcc_abort("source.options_json must contain one JSON object.",
              class = "dcc_plan_error")
  }
  for (name in plan_source_option_names(format)) {
    value <- source[[name]]
    if (!is.null(value) && length(value) == 1L && !is.na(value) &&
        nzchar(trimws(as.character(value)))) {
      options[[name]] <- plan_option_value(name, value)
    }
  }
  options
}

plan_import_spec <- function(plan, data) {
  if (!inherits(plan, "dcc_plan")) {
    dcc_abort("`plan` must be a dcc_plan.", class = "dcc_type_error")
  }
  new_import_spec(
    source = data,
    format = tolower(as.character(plan$source$format)),
    options = plan_import_options(plan),
    columns = plan$columns,
    values = plan$values,
    missing = plan$missing,
    multiselect = plan$multiselect
  )
}

plan_parameters <- function(value, field) {
  parsed <- tryCatch(
    jsonlite::fromJSON(as.character(value), simplifyVector = TRUE),
    error = function(e) {
      dcc_abort("Invalid JSON parameters in ", field, ": ",
                conditionMessage(e), class = "dcc_plan_error")
    }
  )
  if (!is.list(parsed)) {
    dcc_abort(field, " must contain a JSON object.", class = "dcc_plan_error")
  }
  parsed
}

plan_ruleset <- function(plan) {
  checks <- lapply(seq_len(nrow(plan$rules)), function(i) {
    row <- plan$rules[i, ]
    check <- plan_parameters(row$parameters, paste0("rules row ", i))
    check$id <- as.character(row$id)
    check$type <- as.character(row$type)
    variable <- as.character(row$variable)
    if (!is.na(variable) && nzchar(variable)) check$variable <- variable
    check$severity <- as.character(row$severity)
    check
  })
  source <- plan_source_info(plan)$path %||% "<dcc_plan>"
  hash <- if (file.exists(source)) unname(tools::md5sum(source)) else
    hash_import_spec(plan)
  structure(list(checks = checks, source = source, hash = hash),
            class = "dcc_ruleset")
}

plan_actions <- function(plan) {
  actions <- list()
  for (i in seq_len(nrow(plan$actions))) {
    row <- plan$actions[i, ]
    id <- as.character(row$rule_id)
    action <- as.character(row$action)
    parameters <- plan_parameters(row$parameters, paste0("actions row ", i))
    if (action == "recode") {
      map <- parameters$map
      if (is.null(map) || is.null(names(map)) || any(!nzchar(names(map)))) {
        dcc_abort("Recode action `", id, "` needs a named `map` parameter.",
                  class = "dcc_plan_error")
      }
      actions[[id]] <- list(action = "recode", map = unlist(map))
    } else {
      actions[[id]] <- action
    }
  }
  actions
}

plan_config <- function(plan) {
  id_vars <- as.character(plan$columns$name[plan$columns$role == "id"])
  items <- as.character(plan$columns$name[plan$columns$role == "item"])
  dcc_config(
    plan_ruleset(plan), actions = plan_actions(plan),
    id_var = if (length(id_vars)) id_vars[1L] else NULL,
    items = if (length(items)) items else NULL
  )
}

