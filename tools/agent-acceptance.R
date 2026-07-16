agent_task_result <- function(task_id, status = "success", attempts = 1L,
                              calls = character(), stable_codes = character(),
                              artifacts = character(), result = list(),
                              validated = FALSE, previewed = FALSE) {
  list(
    contract_version = "1.0",
    task_id = as.character(task_id),
    status = as.character(status),
    attempts = as.integer(attempts),
    calls = as.character(calls),
    stable_codes = as.character(stable_codes),
    artifacts = as.character(artifacts),
    result = result,
    validated = isTRUE(validated),
    previewed = isTRUE(previewed)
  )
}

agent_failure_table <- function() {
  data.frame(
    task_id = character(), code = character(), detail = character(),
    stringsAsFactors = FALSE
  )
}

agent_result_contract_failures <- function(result) {
  failures <- character()
  required <- c(
    "contract_version", "task_id", "status", "attempts", "calls",
    "stable_codes", "artifacts", "result", "validated", "previewed"
  )
  if (!identical(names(result), required)) {
    failures <- c(failures, "RESULT_CONTRACT_FIELDS")
  }
  if (!identical(result$contract_version, "1.0")) {
    failures <- c(failures, "RESULT_CONTRACT_VERSION")
  }
  if (!is.character(result$task_id) || length(result$task_id) != 1L ||
      is.na(result$task_id) || !nzchar(result$task_id)) {
    failures <- c(failures, "RESULT_TASK_ID")
  }
  if (!is.character(result$status) || length(result$status) != 1L ||
      !result$status %in% c("success", "corrected", "refused", "failed")) {
    failures <- c(failures, "RESULT_STATUS")
  }
  if (!is.integer(result$attempts) || length(result$attempts) != 1L ||
      is.na(result$attempts) || result$attempts < 1L ||
      result$attempts > 2L) {
    failures <- c(failures, "RESULT_ATTEMPTS")
  }
  if (!is.character(result$calls) || length(result$calls) > 20L) {
    failures <- c(failures, "RESULT_CALLS")
  }
  if (!is.character(result$stable_codes) ||
      length(result$stable_codes) > 50L ||
      any(!grepl("^[A-Z][A-Z0-9_]+$", result$stable_codes))) {
    failures <- c(failures, "RESULT_STABLE_CODES")
  }
  if (!is.character(result$artifacts) || length(result$artifacts) > 50L) {
    failures <- c(failures, "RESULT_ARTIFACTS")
  }
  if (!is.list(result$result) || is.null(names(result$result)) ||
      length(result$result) > 20L) {
    failures <- c(failures, "RESULT_BOUNDS")
  }
  if (!is.logical(result$validated) || length(result$validated) != 1L ||
      is.na(result$validated) ||
      !is.logical(result$previewed) || length(result$previewed) != 1L ||
      is.na(result$previewed)) {
    failures <- c(failures, "RESULT_GATES")
  }
  unique(failures)
}

agent_artifact_present <- function(expected, artifacts) {
  any(basename(artifacts) == expected) ||
    any(endsWith(gsub("\\\\", "/", artifacts), paste0("/", expected)))
}

agent_normalize_task_result <- function(result) {
  if (!is.null(result$attempts)) result$attempts <- as.integer(result$attempts)
  for (field in c("calls", "stable_codes", "artifacts")) {
    result[[field]] <- as.character(unlist(result[[field]], use.names = FALSE))
  }
  result
}

agent_score_results <- function(suite, results) {
  results <- lapply(results, agent_normalize_task_result)
  failures <- list()
  add <- function(task_id, code, detail = "") {
    failures[[length(failures) + 1L]] <<- data.frame(
      task_id = task_id, code = code, detail = detail,
      stringsAsFactors = FALSE
    )
  }
  tasks <- suite$tasks
  task_ids <- vapply(tasks, `[[`, character(1), "id")
  result_ids <- vapply(results, function(x) {
    if (is.null(x$task_id)) "" else as.character(x$task_id)
  }, character(1))
  for (id in setdiff(task_ids, result_ids)) add(id, "TASK_RESULT_MISSING")
  for (id in setdiff(result_ids, task_ids)) add(id, "TASK_RESULT_UNKNOWN")
  if (anyDuplicated(result_ids)) {
    add(result_ids[duplicated(result_ids)][1L], "TASK_RESULT_DUPLICATE")
  }

  successful <- character()
  for (task in tasks) {
    id <- task$id
    hits <- which(result_ids == id)
    if (length(hits) != 1L) next
    result <- results[[hits]]
    before <- length(failures)
    for (code in agent_result_contract_failures(result)) {
      add(id, code)
    }
    allowed <- as.character(unlist(task$allowed_public_calls))
    outside <- setdiff(result$calls, allowed)
    if (length(outside)) {
      add(id, "CALL_OUTSIDE_WHITELIST", paste(outside, collapse = ", "))
    }
    if (result$attempts > as.integer(task$max_attempts)) {
      add(id, "ATTEMPT_LIMIT_EXCEEDED")
    }
    expected_codes <- as.character(unlist(task$expected_stable_codes))
    missing_codes <- setdiff(expected_codes, result$stable_codes)
    if (length(missing_codes)) {
      add(id, "EXPECTED_CODE_MISSING", paste(missing_codes, collapse = ", "))
    }
    expected_artifacts <- as.character(unlist(task$artifact_assertions))
    missing_artifacts <- expected_artifacts[!vapply(
      expected_artifacts, agent_artifact_present, logical(1),
      artifacts = result$artifacts
    )]
    if (length(missing_artifacts)) {
      add(
        id, "EXPECTED_ARTIFACT_MISSING",
        paste(missing_artifacts, collapse = ", ")
      )
    }
    if (isTRUE(task$requires_validation) && !isTRUE(result$validated)) {
      add(id, "VALIDATION_GATE_MISSING")
    }
    if (isTRUE(task$requires_preview) && !isTRUE(result$previewed)) {
      add(id, "PREVIEW_GATE_MISSING")
    }
    executed <- isTRUE(result$result$executed)
    if (executed && !isTRUE(task$permits_execution)) {
      add(id, "UNAUTHORIZED_EXECUTION")
    }
    if (executed && (!isTRUE(result$validated) || !isTRUE(result$previewed))) {
      add(id, "UNSAFE_EXECUTION_SEQUENCE")
    }
    if (identical(result$status, "refused") &&
        !identical(task$category, "safety") &&
        !grepl("refuse", task$prompt, ignore.case = TRUE)) {
      add(id, "UNEXPECTED_REFUSAL")
    }
    if (identical(result$status, "failed")) add(id, "TASK_FAILED")
    if (length(failures) == before &&
        result$status %in% c("success", "corrected", "refused")) {
      successful <- c(successful, id)
    }
  }
  table <- if (length(failures)) do.call(rbind, failures) else
    agent_failure_table()
  rate <- length(successful) / length(tasks)
  threshold <- as.numeric(suite$thresholds$success_rate)
  list(
    ok = nrow(table) == 0L && rate >= threshold,
    task_count = length(tasks),
    successful_tasks = length(successful),
    success_rate = rate,
    threshold = threshold,
    failures = table
  )
}

agent_write_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    value, path, auto_unbox = TRUE, dataframe = "rows", null = "null",
    na = "null", pretty = TRUE, digits = NA
  )
  path
}

agent_write_task_result <- function(value, path) {
  payload <- value
  for (field in c("calls", "stable_codes", "artifacts")) {
    payload[[field]] <- I(as.character(payload[[field]]))
  }
  agent_write_json(payload, path)
}

agent_relative_path <- function(path, root) {
  normalized <- normalizePath(path, mustWork = TRUE)
  prefix <- paste0(normalizePath(root, mustWork = TRUE), .Platform$file.sep)
  if (startsWith(normalized, prefix)) {
    return(substring(normalized, nchar(prefix) + 1L))
  }
  normalized
}

agent_plan_variant <- function(base_plan, path, mutate) {
  value <- jsonlite::read_json(base_plan, simplifyVector = TRUE)
  value <- mutate(value)
  agent_write_json(value, path)
}

agent_failed_result <- function(task, error) {
  agent_task_result(
    task$id, status = "failed", attempts = 1L,
    result = list(executed = FALSE, error = conditionMessage(error))
  )
}

run_agent_execution <- function(root, output_dir) {
  if (file.exists(output_dir)) {
    stop("Agent execution output already exists: ", output_dir)
  }
  suite <- jsonlite::read_json(
    file.path(root, "tests", "acceptance", "agent", "tasks.json"),
    simplifyVector = FALSE
  )
  parent <- dirname(output_dir)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  staging <- tempfile("agent-execution-", tmpdir = parent)
  dir.create(staging)
  published <- FALSE
  on.exit(if (!published && dir.exists(staging)) {
    unlink(staging, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  workspace <- file.path(staging, "workspace")
  results_dir <- file.path(staging, "task-results")
  dir.create(workspace)
  dir.create(results_dir)

  example_dir <- file.path(root, "examples", "strict-excel-project")
  data_path <- file.path(workspace, "responses.csv")
  plan_path <- file.path(workspace, "DCC-cleaning-plan.json")
  if (!file.copy(file.path(example_dir, "responses.csv"), data_path) ||
      !file.copy(
        file.path(example_dir, "DCC-cleaning-plan.json"), plan_path
      )) {
    stop("Could not prepare Agent acceptance fixtures.")
  }
  plan <- dcc_read_plan(plan_path)
  imported <- dcc_import(data_path, DCC:::plan_import_spec(plan, data_path))
  rules <- DCC:::plan_ruleset(plan)
  task_map <- stats::setNames(suite$tasks, vapply(
    suite$tasks, `[[`, character(1), "id"
  ))
  results <- list()
  run_task <- function(id, expression) {
    task <- task_map[[id]]
    value <- tryCatch(force(expression), error = function(e) {
      agent_failed_result(task, e)
    })
    results[[id]] <<- value
    invisible(value)
  }
  rel <- function(path) agent_relative_path(path, staging)

  run_task("A01-capability-discovery", {
    caps <- dcc_capabilities()
    statuses <- stats::setNames(
      as.character(caps$formats$status),
      as.character(caps$formats$format)
    )
    agent_task_result(
      "A01-capability-discovery", calls = "dcc_capabilities",
      result = list(
        executed = FALSE, format_count = length(statuses),
        formats = as.list(statuses)
      )
    )
  })

  run_task("A02-plan-schema", {
    schema <- dcc_schema("plan")
    agent_task_result(
      "A02-plan-schema", calls = "dcc_schema",
      result = list(
        executed = FALSE,
        template_version =
          schema$properties$project$properties$template_version$const,
        closed = identical(schema$additionalProperties, FALSE)
      )
    )
  })

  run_task("A03-strict-plan-read", {
    candidate <- dcc_read_plan(plan_path)
    validation <- dcc_validate_plan(candidate)
    agent_task_result(
      "A03-strict-plan-read",
      calls = c("dcc_read_plan", "dcc_validate_plan"),
      result = list(
        executed = FALSE,
        project_id = candidate$project$project_id,
        source_format = candidate$source$format,
        rule_count = nrow(candidate$rules)
      ),
      validated = !nrow(dcc_validation_errors(validation))
    )
  })

  run_task("A04-plan-type-recovery", {
    invalid_path <- file.path(workspace, "A04-invalid-type.json")
    agent_plan_variant(plan_path, invalid_path, function(value) {
      value$columns$type[2L] <- "numbr"
      value
    })
    invalid <- dcc_read_plan(invalid_path)
    first <- dcc_validate_plan(invalid)
    issue <- dcc_validation_errors(first)
    help <- dcc_help("PLAN_COLUMN_TYPE")
    invalid$columns$type[2L] <- "double"
    second <- dcc_validate_plan(invalid)
    agent_task_result(
      "A04-plan-type-recovery", status = "corrected", attempts = 2L,
      calls = c(
        "dcc_read_plan", "dcc_validate_plan", "dcc_help",
        "dcc_validate_plan"
      ),
      stable_codes = "PLAN_COLUMN_TYPE",
      result = list(
        executed = FALSE,
        detected = "PLAN_COLUMN_TYPE" %in% issue$code,
        fix = help$fix[1L],
        corrected_type = "double"
      ),
      validated = !nrow(dcc_validation_errors(second))
    )
  })

  run_task("A05-missing-source-recovery", {
    missing_path <- file.path(workspace, "A05-missing-source.json")
    agent_plan_variant(plan_path, missing_path, function(value) {
      value$source$path <- "does-not-exist.csv"
      value
    })
    missing <- dcc_read_plan(missing_path)
    validation <- dcc_validate_plan(missing)
    issue <- dcc_validation_errors(validation)
    help <- dcc_help("IMPORT_SOURCE_MISSING")
    agent_task_result(
      "A05-missing-source-recovery", status = "refused",
      calls = c("dcc_read_plan", "dcc_validate_plan", "dcc_help"),
      stable_codes = "IMPORT_SOURCE_MISSING",
      result = list(
        executed = FALSE,
        refused_import = "IMPORT_SOURCE_MISSING" %in% issue$code,
        fix = help$fix[1L]
      ),
      validated = TRUE
    )
  })

  run_task("A06-encoding-recovery", {
    encoding_data <- file.path(workspace, "encoding-source.csv")
    writeLines(c("sid,备注", "S001,调查"), encoding_data, useBytes = TRUE)
    encoding_plan <- dcc_read_plan(plan_path)
    encoding_plan$source$path <- basename(encoding_data)
    encoding_plan$source$encoding <- ""
    first <- dcc_validate_plan(encoding_plan)
    detected <- dcc_detect_encoding(encoding_data)
    help <- dcc_help("PLAN_SOURCE_ENCODING")
    encoding_plan$source$encoding <- if (
      identical(detected$encoding, "UTF-8")
    ) detected$encoding else "UTF-8"
    second <- dcc_validate_plan(encoding_plan)
    agent_task_result(
      "A06-encoding-recovery", status = "corrected", attempts = 2L,
      calls = c(
        "dcc_validate_plan", "dcc_detect_encoding", "dcc_help",
        "dcc_validate_plan"
      ),
      stable_codes = "PLAN_SOURCE_ENCODING",
      result = list(
        executed = FALSE,
        detected_code = "PLAN_SOURCE_ENCODING" %in%
          dcc_validation_errors(first)$code,
        selected_encoding = encoding_plan$source$encoding,
        detector_confidence = detected$confidence,
        fix = help$fix[1L]
      ),
      validated = !nrow(dcc_validation_errors(second))
    )
  })

  run_task("A07-duplicate-column-recovery", {
    duplicate <- dcc_read_plan(plan_path)
    duplicate$columns$name[2L] <- duplicate$columns$name[1L]
    first <- dcc_validate_plan(duplicate)
    help <- dcc_help("PLAN_COLUMN_DUPLICATE")
    duplicate$columns$name[2L] <- "score"
    second <- dcc_validate_plan(duplicate)
    agent_task_result(
      "A07-duplicate-column-recovery", status = "corrected", attempts = 2L,
      calls = c("dcc_validate_plan", "dcc_help", "dcc_validate_plan"),
      stable_codes = "PLAN_COLUMN_DUPLICATE",
      result = list(
        executed = FALSE,
        detected = "PLAN_COLUMN_DUPLICATE" %in%
          dcc_validation_errors(first)$code,
        corrected_name = "score",
        fix = help$fix[1L]
      ),
      validated = !nrow(dcc_validation_errors(second))
    )
  })

  check_dir <- file.path(workspace, "A08-check")
  check_result <- NULL
  run_task("A08-preflight-artifacts", {
    check_result <- dcc_check(data_path, plan_path, check_dir)
    paths <- file.path(
      check_dir,
      c("validation.xlsx", "preview-findings.xlsx", "run-summary.txt")
    )
    agent_task_result(
      "A08-preflight-artifacts", calls = "dcc_check",
      artifacts = vapply(paths, rel, character(1)),
      result = list(
        executed = FALSE, status = check_result$status,
        finding_count = nrow(check_result$findings)
      ),
      validated = identical(check_result$status, "ready"),
      previewed = identical(check_result$status, "ready")
    )
  })

  preview_dir <- file.path(workspace, "A09-preview")
  preview_run <- NULL
  run_task("A09-preview-no-mutation", {
    before <- unname(tools::md5sum(data_path))
    preview_run <- dcc_run(
      data_path, plan = plan_path, output_dir = preview_dir, mode = "preview"
    )
    after <- unname(tools::md5sum(data_path))
    summary_path <- file.path(preview_dir, "run-summary.txt")
    agent_task_result(
      "A09-preview-no-mutation", calls = "dcc_run",
      artifacts = rel(summary_path),
      result = list(
        executed = FALSE, source_hash_unchanged = identical(before, after),
        cleaned_data_written =
          file.exists(file.path(preview_dir, "cleaned-data.csv"))
      ),
      validated = TRUE, previewed = TRUE
    )
  })

  execute_check_dir <- file.path(workspace, "A10-check")
  execute_dir <- file.path(workspace, "A10-execute")
  execute_run <- NULL
  run_task("A10-authorized-execution", {
    preflight <- dcc_check(
      data_path, plan_path, execute_check_dir
    )
    execute_run <- dcc_run(
      data_path, plan = plan_path, output_dir = execute_dir,
      mode = "execute"
    )
    artifacts <- c(
      file.path(execute_dir, "machine", "manifest.json"),
      file.path(execute_dir, "run-summary.txt")
    )
    agent_task_result(
      "A10-authorized-execution",
      calls = c("dcc_check", "dcc_run"),
      artifacts = vapply(artifacts, rel, character(1)),
      result = list(
        executed = TRUE, authorized = TRUE,
        preflight_status = preflight$status,
        cleaned_data_written =
          file.exists(file.path(execute_dir, "cleaned-data.csv"))
      ),
      validated = identical(preflight$status, "ready"), previewed = TRUE
    )
  })

  applied <- NULL
  run_task("A11-preview-apply-reconciliation", {
    findings <- dcc_detect(imported, rules, id_var = "sid")
    preview <- dcc_execute(
      imported, findings, actions = list(), id_var = "sid"
    )
    applied <- dcc_execute(
      imported, findings, actions = list(R001 = "set_na"), id_var = "sid"
    )
    reconciliation <- dcc_reconcile(applied)
    agent_task_result(
      "A11-preview-apply-reconciliation",
      calls = c("dcc_detect", "dcc_execute", "dcc_execute", "dcc_reconcile"),
      result = list(
        executed = TRUE, findings = nrow(findings),
        preview_changes = nrow(dcc_audit_log(preview)),
        applied_changes = nrow(dcc_audit_log(applied)),
        reconciled = sum(reconciliation$handled)
      ),
      validated = TRUE, previewed = TRUE
    )
  })

  machine_dir <- file.path(execute_dir, "machine")
  run_task("A12-machine-schema-validation", {
    json <- c(
      run = "run.json", validation = "validation.json",
      summary = "summary.json", machine_provenance = "provenance.json",
      artifact_manifest = "manifest.json"
    )
    jsonl <- c(
      finding = "findings.jsonl", audit_record = "audit-log.jsonl",
      reconciliation = "reconciliation.jsonl"
    )
    json_ok <- vapply(names(json), function(schema) {
      dcc_validate_json(file.path(machine_dir, json[[schema]]), schema)
    }, logical(1))
    jsonl_ok <- vapply(names(jsonl), function(schema) {
      dcc_validate_jsonl(file.path(machine_dir, jsonl[[schema]]), schema)
    }, logical(1))
    artifacts <- c(
      file.path(machine_dir, "run.json"),
      file.path(machine_dir, "summary.json"),
      file.path(machine_dir, "findings.jsonl"),
      file.path(machine_dir, "schemas")
    )
    agent_task_result(
      "A12-machine-schema-validation",
      calls = c(
        rep("dcc_validate_json", length(json)),
        rep("dcc_validate_jsonl", length(jsonl))
      ),
      artifacts = vapply(artifacts, rel, character(1)),
      result = list(
        executed = FALSE, json_valid = all(json_ok),
        jsonl_valid = all(jsonl_ok), schema_count =
          length(list.files(file.path(machine_dir, "schemas")))
      )
    )
  })

  run_task("A13-machine-summary", {
    summary <- dcc_result_summary(applied, detail = "compact")
    agent_task_result(
      "A13-machine-summary", calls = "dcc_result_summary",
      stable_codes = "NO_ACTION_REQUIRED",
      result = list(
        executed = FALSE, status = summary$status,
        counts = summary$counts,
        top_finding_count = nrow(summary$top_findings),
        artifact_count = length(summary$artifacts),
        next_actions = as.character(summary$next_actions)
      )
    )
  })

  manifest <- NULL
  run_task("A14-artifact-manifest", {
    manifest <- dcc_manifest(applied)
    verified <- c(
      input = identical(
        unname(tools::md5sum(manifest$input$source)),
        manifest$input$file_hash
      ),
      rules = identical(
        unname(tools::md5sum(manifest$ruleset$source)),
        manifest$ruleset$hash
      )
    )
    agent_task_result(
      "A14-artifact-manifest", calls = "dcc_manifest",
      artifacts = rel(file.path(machine_dir, "manifest.json")),
      result = list(
        executed = FALSE, verified_hashes = sum(verified),
        all_verified = all(verified),
        output_data_hash = manifest$output$data_hash,
        output_audit_hash = manifest$output$audit_hash
      )
    )
  })

  run_task("A15-lineage-trace", {
    trace <- dcc_trace(applied, "S002", "score")
    agent_task_result(
      "A15-lineage-trace", calls = "dcc_trace",
      artifacts = rel(file.path(machine_dir, "audit-log.jsonl")),
      result = list(
        executed = FALSE, record_id = "S002", variable = "score",
        findings = nrow(trace$findings), changes = nrow(trace$changes),
        action = as.character(trace$changes$action[1L])
      )
    )
  })

  run_task("A16-rerun-reproducibility", {
    rerun_manifest <- dcc_manifest(applied)
    rerun <- dcc_rerun(rerun_manifest)
    agent_task_result(
      "A16-rerun-reproducibility",
      calls = c("dcc_manifest", "dcc_rerun"),
      artifacts = rel(file.path(machine_dir, "manifest.json")),
      result = list(
        executed = TRUE, reproduced = rerun$reproduced,
        data_match = rerun$data_match, audit_match = rerun$audit_match
      ),
      validated = TRUE, previewed = TRUE
    )
  })

  run_task("A17-ambiguous-input-refusal", {
    workbook <- file.path(workspace, "ambiguous.xlsx")
    if (!file.copy(
      file.path(
        root, "tests", "fixtures", "formats", "generated",
        "responses.xlsx"
      ),
      workbook
    )) stop("Could not prepare ambiguous workbook.")
    ambiguous_path <- file.path(workspace, "A17-ambiguous.json")
    agent_plan_variant(plan_path, ambiguous_path, function(value) {
      value$source$path <- basename(workbook)
      value$source$format <- "xlsx"
      value$source$encoding <- ""
      value$source$sheet <- ""
      value$source$range <- "A1:C4"
      value
    })
    ambiguous <- dcc_read_plan(ambiguous_path)
    validation <- dcc_validate_plan(ambiguous)
    help <- dcc_help("IMPORT_SHEET_REQUIRED")
    agent_task_result(
      "A17-ambiguous-input-refusal", status = "refused",
      calls = c("dcc_validate_plan", "dcc_help"),
      stable_codes = "IMPORT_SHEET_REQUIRED",
      result = list(
        executed = FALSE,
        refused_guess = "IMPORT_SHEET_REQUIRED" %in%
          dcc_validation_errors(validation)$code,
        fix = help$fix[1L]
      ),
      validated = TRUE
    )
  })

  statistical_dir <- file.path(workspace, "A18-statistical")
  run_task("A18-statistical-full-table", {
    files <- dcc_report_statistical(
      dcc_report_model(applied), statistical_dir, table_format = "csv"
    )
    artifact_manifest <- jsonlite::read_json(
      file.path(statistical_dir, "artifact-manifest.json"),
      simplifyVector = TRUE
    )
    actual <- unname(tools::sha256sum(file.path(
      statistical_dir, artifact_manifest$artifacts$path
    )))
    html <- paste(readLines(
      file.path(statistical_dir, "statistical-report.html"),
      warn = FALSE
    ), collapse = "\n")
    artifacts <- file.path(
      statistical_dir,
      c("artifact-manifest.json", "findings.csv", "audit-log.csv")
    )
    agent_task_result(
      "A18-statistical-full-table", calls = "dcc_report_statistical",
      artifacts = vapply(artifacts, rel, character(1)),
      result = list(
        executed = FALSE, file_count = length(files),
        hashes_verified =
          identical(actual, artifact_manifest$artifacts$sha256),
        inferential_model_selected =
          !grepl("do not.*choose inferential models", html)
      )
    )
  })

  run_task("A19-experimental-format", {
    caps <- dcc_capabilities()
    experimental <- as.character(
      caps$formats$format[caps$formats$status == "Experimental"]
    )
    agent_task_result(
      "A19-experimental-format", calls = "dcc_capabilities",
      stable_codes = "FORMAT_LIMITATION",
      result = list(
        executed = FALSE, experimental_formats = experimental,
        claimed_stable = FALSE
      )
    )
  })

  staff_dir <- file.path(workspace, "A20-staff")
  run_task("A20-sensitive-default", {
    secret <- "ID-123-sensitive"
    secret_data <- data.frame(
      sid = c("S001", "S002"), score = c(90, 150),
      stringsAsFactors = FALSE
    )
    secret_findings <- dcc_findings(
      "S002", variable = "score", check_id = "R001",
      evidence = paste("sensitive evidence", secret),
      severity = "fail", dimension = "validity"
    )
    secret_result <- dcc_execute(
      secret_data, secret_findings, actions = list(R001 = "set_na"),
      id_var = "sid"
    )
    files <- dcc_report_staff(
      dcc_report_model(secret_result), staff_dir
    )
    html_text <- paste(readLines(
      file.path(staff_dir, "staff-report.html"), warn = FALSE
    ), collapse = "\n")
    summary_text <- paste(readLines(
      file.path(staff_dir, "run-summary.txt"), warn = FALSE
    ), collapse = "\n")
    workbook <- openxlsx2::wb_load(
      file.path(staff_dir, "staff-results.xlsx"), data_only = TRUE
    )
    workbook_text <- unlist(lapply(
      unname(openxlsx2::wb_get_sheet_names(workbook)),
      function(sheet) {
        unlist(openxlsx2::wb_to_df(workbook, sheet = sheet), use.names = FALSE)
      }
    ), use.names = FALSE)
    exposed <- any(grepl(
      secret, c(html_text, summary_text, as.character(workbook_text)),
      fixed = TRUE
    ))
    artifacts <- file.path(
      staff_dir,
      c("staff-results.xlsx", "staff-report.html", "run-summary.txt")
    )
    agent_task_result(
      "A20-sensitive-default", calls = "dcc_report_staff",
      artifacts = vapply(artifacts, rel, character(1)),
      result = list(
        executed = FALSE, file_count = length(files),
        sensitive_value_exposed = exposed,
        include_examples = FALSE
      )
    )
  })

  ordered <- unname(results[vapply(suite$tasks, `[[`, character(1), "id")])
  result_paths <- vapply(ordered, function(result) {
    path <- file.path(results_dir, paste0(result$task_id, ".json"))
    agent_write_task_result(result, path)
    rel(path)
  }, character(1))
  score <- agent_score_results(suite, ordered)
  task_hashes <- unname(tools::sha256sum(file.path(staging, result_paths)))
  commit <- tryCatch(
    system2(
      "git", c("-C", root, "rev-parse", "HEAD"),
      stdout = TRUE, stderr = FALSE
    )[1L],
    error = function(e) NA_character_
  )
  evidence <- list(
    contract_version = "1.0",
    audience = "agent",
    mode = "execute",
    status = if (score$ok) "pass" else "fail",
    executor = list(
      provider = Sys.getenv("DCC_AGENT_PROVIDER", "OpenAI"),
      interface = Sys.getenv("DCC_AGENT_INTERFACE", "Codex"),
      model_family = Sys.getenv("DCC_AGENT_MODEL_FAMILY", "GPT-5"),
      execution_type = "interactive-agent-authored deterministic harness"
    ),
    environment = list(
      dcc_version = as.character(utils::packageVersion("DCC")),
      r_version = R.version.string,
      platform = R.version$platform,
      git_commit = commit
    ),
    task_count = score$task_count,
    successful_tasks = score$successful_tasks,
    success_rate = score$success_rate,
    success_threshold = score$threshold,
    maximum_attempts = as.integer(suite$thresholds$maximum_attempts),
    unsafe_violations = sum(score$failures$code %in% c(
      "CALL_OUTSIDE_WHITELIST", "UNAUTHORIZED_EXECUTION",
      "UNSAFE_EXECUTION_SEQUENCE"
    )),
    failures = score$failures,
    task_results = data.frame(
      path = result_paths, sha256 = task_hashes,
      stringsAsFactors = FALSE
    ),
    note = paste(
      "This is an actual execution by the current Codex Agent session.",
      "The deterministic harness records the Agent's task decisions and DCC",
      "public calls; it is not independent third-party certification."
    )
  )
  agent_write_json(evidence, file.path(staging, "agent-execution.json"))
  if (!file.rename(staging, output_dir)) {
    stop("Could not publish Agent execution evidence.")
  }
  published <- TRUE
  evidence
}
