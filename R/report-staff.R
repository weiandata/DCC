#' Render the staff workbook and HTML report
#'
#' Produces concise bilingual reports from a validated normalized report model.
#' Potentially identifying examples are masked unless explicitly requested.
#'
#' @param model A [dcc_report_model()] object.
#' @param output_dir Existing or new directory for report files.
#' @param formats Any combination of `"xlsx"` and `"html"`.
#' @param language Primary display language, `"zh-CN"` or `"en"`.
#' @param include_examples Whether raw evidence and before/after values may be
#'   included. Defaults to `FALSE`.
#' @return Character paths of the files written, including
#'   `run-summary.txt`.
#' @export
dcc_report_staff <- function(model, output_dir,
                             formats = c("xlsx", "html"),
                             language = c("zh-CN", "en"),
                             include_examples = FALSE) {
  staff_validate_model(model)
  language <- match.arg(language)
  if (!is.character(formats) || !length(formats) || anyNA(formats) ||
      any(!formats %in% c("xlsx", "html"))) {
    dcc_abort("`formats` must contain only `xlsx` and/or `html`.",
              class = "dcc_report_error")
  }
  formats <- unique(formats)
  if (!is.logical(include_examples) || length(include_examples) != 1L ||
      is.na(include_examples)) {
    dcc_abort("`include_examples` must be TRUE or FALSE.",
              class = "dcc_report_error")
  }
  if (!is.character(output_dir) || length(output_dir) != 1L ||
      is.na(output_dir) || !nzchar(output_dir)) {
    dcc_abort("`output_dir` must be one directory path.",
              class = "dcc_report_error")
  }

  tables <- staff_report_tables(model, language, include_examples)
  staff_preflight_rows(vapply(tables, nrow, integer(1)))
  targets <- c(
    if ("xlsx" %in% formats) file.path(output_dir, "staff-results.xlsx"),
    if ("html" %in% formats) file.path(output_dir, "staff-report.html"),
    file.path(output_dir, "run-summary.txt")
  )
  collisions <- targets[file.exists(targets)]
  if (length(collisions)) {
    dcc_abort("Report output already exists: ", collisions[1L],
              class = "dcc_report_error")
  }
  if (!dir.exists(output_dir) &&
      !dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)) {
    dcc_abort("Could not create report directory: ", output_dir,
              class = "dcc_report_error")
  }

  written <- character()
  if ("xlsx" %in% formats) {
    path <- file.path(output_dir, "staff-results.xlsx")
    write_staff_workbook(tables, path)
    written <- c(written, path)
  }
  if ("html" %in% formats) {
    path <- file.path(output_dir, "staff-report.html")
    write_staff_html(model, tables, path, language, include_examples,
                     workbook = "xlsx" %in% formats)
    written <- c(written, path)
  }
  summary <- file.path(output_dir, "run-summary.txt")
  write_staff_summary(model, summary, language, include_examples)
  written <- c(written, summary)
  normalizePath(written, mustWork = TRUE)
}

staff_validate_model <- function(model) {
  if (!inherits(model, "dcc_report_model")) {
    dcc_abort("`model` must be a dcc_report_model.", class = "dcc_type_error")
  }
  errors <- dcc_validation_errors(dcc_validate_report_model(model))
  if (nrow(errors)) {
    dcc_abort("Invalid report model (", errors$code[1L], ").",
              class = "dcc_report_error")
  }
  invisible(TRUE)
}

staff_preflight_rows <- function(rows) {
  # One header row is also written; Excel has 1,048,576 total rows.
  invalid <- names(rows)[rows > 1048575L]
  if (length(invalid)) {
    dcc_abort("Excel row limit would be exceeded on sheet '", invalid[1L],
              "'; no rows were truncated.", class = "dcc_report_error")
  }
  invisible(TRUE)
}

staff_report_tables <- function(model, language, include_examples) {
  labels <- staff_labels(language)
  overview <- data.frame(
    key = c(
      "run_id", "status", "input_rows", "output_rows", "findings_total",
      "changes_total", "excluded_total", "handled_total", "unhandled_total",
      "examples_included", "cleaned_data_hash", "audit_log_hash"
    ),
    label = labels$overview,
    value = c(
      NA_real_, NA_real_, model$summaries$input_rows,
      model$summaries$output_rows, model$summaries$findings_total,
      model$summaries$changes_total, model$summaries$excluded_total,
      model$summaries$handled_total, model$summaries$unhandled_total,
      as.integer(include_examples), NA_real_, NA_real_
    ),
    display_value = as.character(c(
      model$run$run_id, model$run$status, model$summaries$input_rows,
      model$summaries$output_rows, model$summaries$findings_total,
      model$summaries$changes_total, model$summaries$excluded_total,
      model$summaries$handled_total, model$summaries$unhandled_total,
      include_examples, model$hashes$cleaned_data, model$hashes$audit_log
    )),
    stringsAsFactors = FALSE
  )
  validation <- staff_redact_table(model$validation, include_examples)
  blocking <- validation[validation$severity == "fail", , drop = FALSE]
  findings <- data.table::as.data.table(model$findings)
  if (nrow(findings)) {
    group <- intersect(c("code", "check_id", "severity", "dimension"),
                       names(findings))
    issues <- as.data.frame(
      findings[, list(count = sum(count)), by = group][
        order(-count, severity, check_id)
      ],
      stringsAsFactors = FALSE
    )
  } else {
    issues <- data.frame(
      code = character(), check_id = character(), severity = character(),
      dimension = character(), count = integer(), stringsAsFactors = FALSE
    )
  }
  review <- model$reconciliation
  if (nrow(review)) {
    review <- review[
      review$status %in% c("unhandled", "failed", "flagged", "skipped") |
        review$severity == "fail",
      , drop = FALSE
    ]
  }
  review <- staff_redact_table(review, include_examples)
  changes <- staff_redact_table(model$changes, include_examples)
  exclusions <- staff_redact_table(model$exclusions, include_examples)
  outputs <- model$outputs
  if (!"description" %in% names(outputs)) {
    outputs$description <- if (nrow(outputs)) {
      rep(labels$output_description, nrow(outputs))
    } else character()
  }
  list(
    `运行概览` = overview,
    `导入检查` = validation,
    `阻断错误` = blocking,
    `问题汇总` = issues,
    `需要复核` = review,
    `已应用更改` = changes,
    `排除记录` = exclusions,
    `输出文件说明` = outputs
  )
}

staff_redact_table <- function(x, include_examples) {
  out <- as.data.frame(x, stringsAsFactors = FALSE)
  if (include_examples || !ncol(out)) return(out)
  sensitive <- intersect(
    c("evidence", "old_value", "new_value", "source_value", "example"),
    names(out)
  )
  for (name in sensitive) {
    present <- !is.na(out[[name]]) & nzchar(as.character(out[[name]]))
    out[[name]][present] <- "[REDACTED]"
  }
  out
}

staff_labels <- function(language, include_examples = FALSE) {
  zh <- c(
    "运行编号 / Run ID", "运行状态 / Status", "输入行数 / Input rows",
    "输出行数 / Output rows", "问题总数 / Findings",
    "更改记录数 / Changes", "排除记录数 / Exclusions",
    "已处理问题 / Handled", "未处理问题 / Unhandled",
    "是否显示原始示例 / Raw examples included",
    "清洗数据哈希 / Cleaned-data hash", "审计日志哈希 / Audit-log hash"
  )
  en <- c(
    "Run ID / 运行编号", "Status / 运行状态", "Input rows / 输入行数",
    "Output rows / 输出行数", "Findings / 问题总数",
    "Changes / 更改记录数", "Exclusions / 排除记录数",
    "Handled / 已处理问题", "Unhandled / 未处理问题",
    "Raw examples included / 是否显示原始示例",
    "Cleaned-data hash / 清洗数据哈希", "Audit-log hash / 审计日志哈希"
  )
  list(
    title = if (language == "zh-CN") {
      "DCC 工作人员结果报告 / Staff results report"
    } else {
      "DCC Staff Results Report / 工作人员结果报告"
    },
    overview = if (language == "zh-CN") zh else en,
    output_description = if (language == "zh-CN") {
      "本次运行生成的文件 / File produced by this run"
    } else {
      "File produced by this run / 本次运行生成的文件"
    },
    redaction = if (!include_examples) {
      "原始示例已隐藏；只有明确启用 include_examples 才会显示。 / Raw examples are hidden unless include_examples is enabled."
    } else {
      "已明确启用原始示例；本报告可能包含敏感值。 / Raw examples were explicitly enabled; this report may contain sensitive values."
    }
  )
}

write_staff_workbook <- function(tables, path) {
  wb <- openxlsx2::wb_workbook(
    creator = "DCC", title = "DCC staff results",
    company = "WEIAN DATA TECH (Beijing) Co., Ltd."
  )
  wb <- openxlsx2::wb_set_base_font(wb, font_size = 10, font_name = "Aptos")
  hidden_keys <- c("key", "value", "finding_id", "code", "detector_id")
  for (sheet in names(tables)) {
    table <- as.data.frame(tables[[sheet]], stringsAsFactors = FALSE)
    machine_names <- names(table)
    if (!identical(sheet, "运行概览")) {
      names(table) <- staff_header_labels(machine_names)
    }
    wb <- openxlsx2::wb_add_worksheet(wb, sheet, grid_lines = FALSE, zoom = 90)
    if (nrow(table)) {
      wb <- openxlsx2::wb_add_data(wb, sheet, table, with_filter = TRUE,
                                   na = "")
    } else {
      wb <- openxlsx2::wb_add_data(wb, sheet, as.list(names(table)),
                                   col_names = FALSE)
    }
    if (!ncol(table)) next
    last_col <- openxlsx2::int2col(ncol(table))
    header <- paste0("A1:", last_col, "1")
    used <- paste0("A1:", last_col, max(1L, nrow(table) + 1L))
    wb <- openxlsx2::wb_add_fill(
      wb, sheet, header, color = openxlsx2::wb_color(hex = "FF1F4E78")
    )
    wb <- openxlsx2::wb_add_font(
      wb, sheet, header, color = openxlsx2::wb_color(hex = "FFFFFFFF"),
      bold = TRUE, size = 11
    )
    wb <- openxlsx2::wb_add_cell_style(
      wb, sheet, used, vertical = "center", wrap_text = TRUE
    )
    wb <- openxlsx2::wb_set_row_heights(wb, sheet, 1, 26)
    if (nrow(table)) {
      wb <- openxlsx2::wb_set_row_heights(
        wb, sheet, rows = seq.int(2L, nrow(table) + 1L), heights = 30
      )
    }
    wb <- openxlsx2::wb_freeze_pane(wb, sheet, first_active_row = 2)
    wb <- openxlsx2::wb_set_sheetview(
      wb, sheet, show_grid_lines = FALSE, zoom_scale = 90
    )
    for (j in seq_along(table)) {
      wb <- openxlsx2::wb_set_col_widths(
        wb, sheet, cols = j,
        widths = workbook_column_width(table[[j]], names(table)[j]),
        hidden = machine_names[j] %in% hidden_keys
      )
    }
  }
  openxlsx2::wb_save(wb, path, overwrite = FALSE)
  invisible(path)
}

staff_header_labels <- function(names) {
  labels <- c(
    record_id = "记录编号 / Record ID",
    variable = "变量 / Variable",
    check_id = "规则编号 / Rule ID",
    evidence = "示例 / Example",
    severity = "严重程度 / Severity",
    dimension = "质量维度 / Dimension",
    count = "数量 / Count",
    action = "处理动作 / Action",
    status = "状态 / Status",
    message = "说明 / Message",
    handled = "已处理 / Handled",
    old_value = "原值 / Old value",
    new_value = "新值 / New value",
    method = "处理方法 / Method",
    timestamp = "时间 / Timestamp",
    dcc_version = "DCC 版本 / DCC version",
    ruleset_hash = "规则哈希 / Ruleset hash",
    keyfile_hash = "密钥文件哈希 / Key-file hash",
    field = "字段 / Field",
    rows = "行 / Rows",
    fix = "修复建议 / Suggested fix",
    workbook = "工作簿 / Workbook",
    sheet = "工作表 / Sheet",
    row = "行号 / Row",
    column = "列 / Column",
    cell = "单元格 / Cell",
    name = "文件名 / File name",
    path = "路径 / Path",
    description = "文件说明 / Description"
  )
  out <- unname(labels[names])
  out[is.na(out)] <- names[is.na(out)]
  out
}

write_staff_html <- function(model, tables, path, language, include_examples,
                             workbook) {
  labels <- staff_labels(language, include_examples)
  css_path <- system.file("templates", "report-staff.css", package = "DCC")
  css <- if (nzchar(css_path)) paste(readLines(css_path, warn = FALSE),
                                    collapse = "\n") else ""
  review <- utils::head(tables[["需要复核"]], 20L)
  issues <- utils::head(tables[["问题汇总"]], 20L)
  html <- c(
    "<!doctype html><html><head><meta charset='utf-8'>",
    paste0("<title>", html_escape(labels$title), "</title><style>", css,
           "</style></head><body>"),
    paste0("<h1>", html_escape(labels$title), "</h1>"),
    paste0("<p class='notice'>", html_escape(labels$redaction), "</p>"),
    paste0("<p><code>run_id</code>: ", html_escape(model$run$run_id),
           " &nbsp; <code>status</code>: ", html_escape(model$run$status),
           " &nbsp; <code>examples_included</code>: ",
           tolower(as.character(include_examples)), "</p>"),
    "<h2>运行概览 / Run overview</h2>",
    html_table(tables[["运行概览"]][
      , c("label", "display_value"), drop = FALSE
    ]),
    "<h2>问题汇总 / Findings summary</h2>",
    if (nrow(issues)) html_table(issues) else "<p>无 / None</p>",
    "<h2>需要复核 / Needs review</h2>",
    if (nrow(review)) html_table(review) else "<p>无 / None</p>",
    if (workbook) {
      "<p><a href='staff-results.xlsx'>完整表格 / Full workbook</a></p>"
    } else "",
    "</body></html>"
  )
  writeLines(html, path, useBytes = TRUE)
  invisible(path)
}

write_staff_summary <- function(model, path, language, include_examples) {
  title <- if (language == "zh-CN") {
    "DCC 运行摘要 / Run summary"
  } else "DCC Run Summary / 运行摘要"
  writeLines(c(
    title,
    paste0("run_id: ", model$run$run_id),
    paste0("status: ", model$run$status),
    paste0("input_rows: ", model$summaries$input_rows),
    paste0("output_rows: ", model$summaries$output_rows),
    paste0("findings_total: ", model$summaries$findings_total),
    paste0("changes_total: ", model$summaries$changes_total),
    paste0("excluded_total: ", model$summaries$excluded_total),
    paste0("examples_included: ", toupper(as.character(include_examples)))
  ), path, useBytes = TRUE)
  invisible(path)
}
