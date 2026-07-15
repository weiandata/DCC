flatten_validation <- function(x) {
  out <- as.data.frame(x, stringsAsFactors = FALSE)
  out$rows <- vapply(x$rows, function(rows) paste(rows, collapse = ","),
                     character(1))
  out
}

write_check_validation <- function(validation, path) {
  issues <- flatten_validation(validation)
  summary <- data.frame(
    metric = c("blocking_issues", "warnings", "total_issues"),
    value = c(sum(validation$severity == "fail"),
              sum(validation$severity == "warn"), nrow(validation)),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(list(summary = summary, issues = issues), path)
}

check_report_labels <- function(language) {
  if (language == "zh-CN") {
    list(title = "DCC 数据检查报告 / Data check report",
         status = "检查状态 / Status", issues = "问题 / Issues",
         findings = "预览发现 / Preview findings",
         safe = "原始数据未修改；本次检查未执行任何清洗动作。",
         none = "无 / None")
  } else {
    list(title = "DCC Data Check Report / 数据检查报告",
         status = "Status / 检查状态", issues = "Issues / 问题",
         findings = "Preview findings / 预览发现",
         safe = "Raw data was not changed; no cleaning action was executed.",
         none = "None / 无")
  }
}

write_staff_check_report <- function(plan, validation, findings, status, path) {
  language <- as.character(plan$project$language %||% "zh-CN")
  labels <- check_report_labels(language)
  issue_table <- flatten_validation(validation)
  if (nrow(issue_table)) {
    issue_table <- issue_table[, c("code", "severity", "sheet", "cell", "fix"),
                               drop = FALSE]
  }
  finding_table <- as.data.frame(findings, stringsAsFactors = FALSE)
  if (nrow(finding_table)) {
    keep <- intersect(c("record_id", "variable", "check_id", "severity",
                        "evidence"), names(finding_table))
    finding_table <- finding_table[, keep, drop = FALSE]
  }
  html <- c(
    "<!doctype html><html><head><meta charset='utf-8'>",
    paste0("<title>", html_escape(labels$title), "</title>"),
    "<style>body{font-family:Arial,'Microsoft YaHei',sans-serif;margin:2em;max-width:1100px}h1{color:#1f4e78}.safe{background:#e2f0d9;padding:12px;border-left:5px solid #70ad47}table{border-collapse:collapse;width:100%;margin:1em 0}th,td{border-bottom:1px solid #d9e2f3;padding:7px;text-align:left}th{background:#1f4e78;color:white}.fail{color:#c00000}</style></head><body>",
    paste0("<h1>", html_escape(labels$title), "</h1>"),
    paste0("<p class='safe'>", html_escape(labels$safe), "</p>"),
    paste0("<h2>", html_escape(labels$status), "</h2><p><strong>",
           html_escape(status), "</strong></p>"),
    paste0("<h2>", html_escape(labels$issues), "</h2>"),
    if (nrow(issue_table)) html_table(issue_table) else
      paste0("<p>", html_escape(labels$none), "</p>"),
    paste0("<h2>", html_escape(labels$findings), "</h2>"),
    if (nrow(finding_table)) html_table(finding_table) else
      paste0("<p>", html_escape(labels$none), "</p>"),
    "</body></html>"
  )
  writeLines(html, path, useBytes = TRUE)
}

bind_check_validations <- function(...) {
  reports <- list(...)
  reports <- Filter(function(x) inherits(x, "dcc_validation"), reports)
  if (!length(reports)) return(empty_validation())
  out <- data.table::rbindlist(reports, use.names = TRUE, fill = TRUE)
  data.table::setattr(out, "class",
                      c("dcc_validation", class(data.table::data.table())))
  out[]
}

new_check_issue <- function(code, field, fix, plan) {
  locate_plan_validation(new_validation(list(
    val_issue(code, "fail", field, fix = fix)
  )), plan)
}

publish_check <- function(staging, output_dir) {
  if (!file.rename(staging, output_dir)) {
    dcc_abort("Could not publish check directory: ", output_dir,
              class = "dcc_check_error")
  }
  output_dir
}

#' Check a strict DCC project without changing data
#'
#' Validates the plan, performs a strict canonical import, runs environment and
#' data checks, and previews findings. It writes diagnostics and a bilingual
#' staff report only; no action, cleaned dataset, audit log, or manifest is
#' produced.
#'
#' @param data Existing source data file path.
#' @param plan Strict `.xlsx`/`.json` plan path or a `dcc_plan`.
#' @param output_dir New directory for check diagnostics.
#' @return A `dcc_check_result` with status, validation, findings, imported data,
#'   and written files.
#' @export
dcc_check <- function(data, plan, output_dir = "dcc-check") {
  if (!is.character(data) || length(data) != 1L || is.na(data) ||
      !file.exists(data)) {
    dcc_abort("`data` must be one existing source file path.",
              class = "dcc_check_error")
  }
  if (!is.character(output_dir) || length(output_dir) != 1L ||
      is.na(output_dir) || !nzchar(output_dir) || file.exists(output_dir)) {
    dcc_abort("`output_dir` must be one new directory path.",
              class = "dcc_check_error")
  }
  plan <- if (inherits(plan, "dcc_plan")) plan else dcc_read_plan(plan)
  parent <- dirname(output_dir)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    dcc_abort("Could not create output parent: ", parent,
              class = "dcc_check_error")
  }
  staging <- paste0(output_dir, ".staging-", new_run_id())
  if (!dir.create(staging)) {
    dcc_abort("Could not create check staging directory.",
              class = "dcc_check_error")
  }
  published <- FALSE
  on.exit(if (!published && dir.exists(staging))
    unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)

  validation <- dcc_validate_plan(plan)
  findings <- empty_findings()
  imported <- NULL
  config <- NULL
  if (!nrow(dcc_validation_errors(validation))) {
    prepared <- tryCatch({
      spec <- plan_import_spec(plan, data)
      imported <- dcc_import(data, spec)
      config <- plan_config(plan)
      list(imported = imported, config = config)
    }, error = function(e) e)
    if (inherits(prepared, "error")) {
      validation <- bind_check_validations(
        validation,
        new_check_issue("CHECK_IMPORT_FAILED", "source.path",
                        conditionMessage(prepared), plan)
      )
    } else {
      imported <- prepared$imported
      config <- prepared$config
      validation <- bind_check_validations(
        validation, dcc_validate_config(config),
        dcc_doctor(imported, config$rules, config$id_var)
      )
      if (!nrow(dcc_validation_errors(validation))) {
        detected <- tryCatch(
          dcc_detect(imported, config$rules, id_var = config$id_var),
          error = function(e) e
        )
        if (inherits(detected, "error")) {
          validation <- bind_check_validations(
            validation,
            new_check_issue("CHECK_DETECTION_FAILED", "rules",
                            conditionMessage(detected), plan)
          )
        } else {
          findings <- detected
        }
      }
    }
  }
  status <- if (nrow(dcc_validation_errors(validation))) "invalid" else "ready"
  validation_path <- file.path(staging, "validation.xlsx")
  write_check_validation(validation, validation_path)
  files <- validation_path
  if (status == "ready") {
    findings_path <- file.path(staging, "preview-findings.xlsx")
    writexl::write_xlsx(as.data.frame(findings), findings_path)
    files <- c(files, findings_path)
  }
  report_path <- file.path(staging, "staff-report.html")
  write_staff_check_report(plan, validation, findings, status, report_path)
  summary_path <- file.path(staging, "run-summary.txt")
  writeLines(c(
    "DCC check summary / DCC 检查摘要",
    paste0("status: ", status),
    paste0("blocking_issues: ", sum(validation$severity == "fail")),
    paste0("findings: ", nrow(findings)),
    "raw_data_changed: FALSE",
    "actions_executed: FALSE"
  ), summary_path, useBytes = TRUE)
  files <- c(files, report_path, summary_path)

  target <- publish_check(staging, output_dir)
  published <- TRUE
  files <- published_paths(files, staging, target)
  structure(
    list(status = status, plan = plan, validation = validation,
         findings = findings, data = imported, config = config, files = files,
         output_dir = target),
    class = "dcc_check_result"
  )
}

#' @export
print.dcc_check_result <- function(x, ...) {
  cat(sprintf("<dcc_check_result> %s; %d issue(s), %d finding(s)\n",
              x$status, nrow(x$validation), nrow(x$findings)))
  invisible(x)
}

