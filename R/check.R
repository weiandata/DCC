flatten_validation <- function(x) {
  out <- as.data.frame(x, stringsAsFactors = FALSE)
  out$rows <- vapply(x$rows, function(rows) paste(rows, collapse = ","),
                     character(1))
  out
}

workbook_column_width <- function(x, name) {
  values <- c(name, as.character(utils::head(x, 200L)))
  width <- suppressWarnings(max(nchar(values, type = "width"), na.rm = TRUE))
  min(50, max(12, width + 2))
}

write_tabular_workbook <- function(tables, path) {
  wb <- openxlsx2::wb_workbook(
    creator = "DCC", title = "DCC diagnostics",
    company = "WEIAN DATA TECH (Beijing) Co., Ltd."
  )
  wb <- openxlsx2::wb_set_base_font(wb, font_size = 10, font_name = "Aptos")
  for (sheet in names(tables)) {
    table <- as.data.frame(tables[[sheet]], stringsAsFactors = FALSE)
    wb <- openxlsx2::wb_add_worksheet(wb, sheet, grid_lines = FALSE, zoom = 90)
    if (nrow(table)) {
      wb <- openxlsx2::wb_add_data(wb, sheet, table, with_filter = TRUE)
    } else {
      wb <- openxlsx2::wb_add_data(wb, sheet, as.list(names(table)),
                                  col_names = FALSE)
    }
    last_col <- openxlsx2::int2col(ncol(table))
    header <- paste0("A1:", last_col, "1")
    wb <- openxlsx2::wb_add_fill(
      wb, sheet, header, color = openxlsx2::wb_color(hex = "FF1F4E78")
    )
    wb <- openxlsx2::wb_add_font(
      wb, sheet, header, color = openxlsx2::wb_color(hex = "FFFFFFFF"),
      bold = TRUE
    )
    wb <- openxlsx2::wb_add_cell_style(
      wb, sheet, header, vertical = "center", wrap_text = TRUE
    )
    wb <- openxlsx2::wb_set_row_heights(wb, sheet, 1, 24)
    wb <- openxlsx2::wb_freeze_pane(wb, sheet, first_active_row = 2)
    wb <- openxlsx2::wb_set_sheetview(wb, sheet, show_grid_lines = FALSE,
                                      zoom_scale = 90)
    for (j in seq_along(table)) {
      wb <- openxlsx2::wb_set_col_widths(
        wb, sheet, cols = j,
        widths = workbook_column_width(table[[j]], names(table)[j])
      )
    }
  }
  openxlsx2::wb_save(wb, path, overwrite = FALSE)
  invisible(path)
}

write_check_validation <- function(validation, path) {
  issues <- flatten_validation(validation)
  summary <- data.frame(
    metric = c("blocking_issues", "warnings", "total_issues"),
    value = c(sum(validation$severity == "fail"),
              sum(validation$severity == "warn"), nrow(validation)),
    stringsAsFactors = FALSE
  )
  write_tabular_workbook(list(summary = summary, issues = issues), path)
}

check_report_labels <- function(language) {
  if (language == "zh-CN") {
    list(title = "DCC \u6570\u636e\u68c0\u67e5\u62a5\u544a / Data check report",
         status = "\u68c0\u67e5\u72b6\u6001 / Status",
         issues = "\u95ee\u9898 / Issues",
         findings = "\u9884\u89c8\u53d1\u73b0 / Preview findings",
         safe = paste0("\u539f\u59cb\u6570\u636e\u672a\u4fee\u6539\uff1b",
                       "\u672c\u6b21\u68c0\u67e5\u672a\u6267\u884c",
                       "\u4efb\u4f55\u6e05\u6d17\u52a8\u4f5c\u3002"),
         none = "\u65e0 / None")
  } else {
    list(title = paste0("DCC Data Check Report / ",
                        "\u6570\u636e\u68c0\u67e5\u62a5\u544a"),
         status = "Status / \u68c0\u67e5\u72b6\u6001",
         issues = "Issues / \u95ee\u9898",
         findings = "Preview findings / \u9884\u89c8\u53d1\u73b0",
         safe = "Raw data was not changed; no cleaning action was executed.",
         none = "None / \u65e0")
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
    staff_findings <- as.data.frame(findings)
    preferred <- c("record_id", "variable", "check_id", "code", "severity",
                   "evidence", "dimension", "detector_id", "finding_id")
    staff_findings <- staff_findings[
      , c(intersect(preferred, names(staff_findings)),
          setdiff(names(staff_findings), preferred)), drop = FALSE
    ]
    write_tabular_workbook(
      list(findings = staff_findings), findings_path
    )
    files <- c(files, findings_path)
  }
  report_path <- file.path(staging, "staff-report.html")
  write_staff_check_report(plan, validation, findings, status, report_path)
  summary_path <- file.path(staging, "run-summary.txt")
  writeLines(c(
    "DCC check summary / DCC \u68c0\u67e5\u6458\u8981",
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
