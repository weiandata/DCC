resolve_run_inputs <- function(data, config, plan, mode) {
  if (!is.null(config) && !is.null(plan)) {
    dcc_abort("Supply `config` or `plan`, not both.", class = "dcc_run_error")
  }
  if (!is.null(plan)) {
    if (mode == "rerun") {
      dcc_abort("`plan` is not used in rerun mode; supply the original ",
                "dcc_config and manifest.", class = "dcc_run_error")
    }
    if (!is.character(data) || length(data) != 1L || is.na(data) ||
        !file.exists(data)) {
      dcc_abort("Plan-based runs require one existing source file path.",
                class = "dcc_run_error")
    }
    project <- if (inherits(plan, "dcc_plan")) plan else dcc_read_plan(plan)
    errors <- dcc_validation_errors(dcc_validate_plan(project))
    if (nrow(errors)) {
      location <- if (nzchar(errors$cell[1L])) {
        paste0(" at ", errors$sheet[1L], "!", errors$cell[1L])
      } else {
        ""
      }
      dcc_abort("Plan validation failed: ", errors$code[1L], location,
                " (", errors$fix[1L], ")", class = "dcc_run_error")
    }
    resolved <- tryCatch({
      spec <- plan_import_spec(project, data)
      list(data = dcc_import(data, spec), config = plan_config(project),
           plan = project)
    }, error = function(e) {
      dcc_abort("Could not prepare plan-based run: ", conditionMessage(e),
                class = "dcc_run_error")
    })
    config_errors <- dcc_validation_errors(
      dcc_validate_config(resolved$config)
    )
    if (nrow(config_errors)) {
      dcc_abort("Compiled plan is invalid: ", config_errors$code[1L], " (",
                config_errors$fix[1L], ")", class = "dcc_run_error")
    }
    return(resolved)
  }
  if (!inherits(config, "dcc_config")) {
    dcc_abort("Supply a dcc_config in `config` or a strict plan in `plan`.",
              class = "dcc_run_error")
  }
  list(data = data, config = config, plan = NULL)
}

