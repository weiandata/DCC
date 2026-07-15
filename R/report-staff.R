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
  tables <- list(
    overview, validation, blocking, issues, review, changes, exclusions,
    outputs
  )
  names(tables) <- c(
    "\u8fd0\u884c\u6982\u89c8", "\u5bfc\u5165\u68c0\u67e5",
    "\u963b\u65ad\u9519\u8bef", "\u95ee\u9898\u6c47\u603b",
    "\u9700\u8981\u590d\u6838", "\u5df2\u5e94\u7528\u66f4\u6539",
    "\u6392\u9664\u8bb0\u5f55", "\u8f93\u51fa\u6587\u4ef6\u8bf4\u660e"
  )
  tables
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
    "\u8fd0\u884c\u7f16\u53f7 / Run ID", "\u8fd0\u884c\u72b6\u6001 / Status", "\u8f93\u5165\u884c\u6570 / Input rows",
    "\u8f93\u51fa\u884c\u6570 / Output rows", "\u95ee\u9898\u603b\u6570 / Findings",
    "\u66f4\u6539\u8bb0\u5f55\u6570 / Changes", "\u6392\u9664\u8bb0\u5f55\u6570 / Exclusions",
    "\u5df2\u5904\u7406\u95ee\u9898 / Handled", "\u672a\u5904\u7406\u95ee\u9898 / Unhandled",
    "\u662f\u5426\u663e\u793a\u539f\u59cb\u793a\u4f8b / Raw examples included",
    "\u6e05\u6d17\u6570\u636e\u54c8\u5e0c / Cleaned-data hash", "\u5ba1\u8ba1\u65e5\u5fd7\u54c8\u5e0c / Audit-log hash"
  )
  en <- c(
    "Run ID / \u8fd0\u884c\u7f16\u53f7", "Status / \u8fd0\u884c\u72b6\u6001", "Input rows / \u8f93\u5165\u884c\u6570",
    "Output rows / \u8f93\u51fa\u884c\u6570", "Findings / \u95ee\u9898\u603b\u6570",
    "Changes / \u66f4\u6539\u8bb0\u5f55\u6570", "Exclusions / \u6392\u9664\u8bb0\u5f55\u6570",
    "Handled / \u5df2\u5904\u7406\u95ee\u9898", "Unhandled / \u672a\u5904\u7406\u95ee\u9898",
    "Raw examples included / \u662f\u5426\u663e\u793a\u539f\u59cb\u793a\u4f8b",
    "Cleaned-data hash / \u6e05\u6d17\u6570\u636e\u54c8\u5e0c", "Audit-log hash / \u5ba1\u8ba1\u65e5\u5fd7\u54c8\u5e0c"
  )
  list(
    title = if (language == "zh-CN") {
      "DCC \u5de5\u4f5c\u4eba\u5458\u7ed3\u679c\u62a5\u544a / Staff results report"
    } else {
      "DCC Staff Results Report / \u5de5\u4f5c\u4eba\u5458\u7ed3\u679c\u62a5\u544a"
    },
    overview = if (language == "zh-CN") zh else en,
    output_description = if (language == "zh-CN") {
      "\u672c\u6b21\u8fd0\u884c\u751f\u6210\u7684\u6587\u4ef6 / File produced by this run"
    } else {
      "File produced by this run / \u672c\u6b21\u8fd0\u884c\u751f\u6210\u7684\u6587\u4ef6"
    },
    redaction = if (!include_examples) {
      "\u539f\u59cb\u793a\u4f8b\u5df2\u9690\u85cf\uff1b\u53ea\u6709\u660e\u786e\u542f\u7528 include_examples \u624d\u4f1a\u663e\u793a\u3002 / Raw examples are hidden unless include_examples is enabled."
    } else {
      "\u5df2\u660e\u786e\u542f\u7528\u539f\u59cb\u793a\u4f8b\uff1b\u672c\u62a5\u544a\u53ef\u80fd\u5305\u542b\u654f\u611f\u503c\u3002 / Raw examples were explicitly enabled; this report may contain sensitive values."
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
    if (!identical(sheet, "\u8fd0\u884c\u6982\u89c8")) {
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
    record_id = "\u8bb0\u5f55\u7f16\u53f7 / Record ID",
    variable = "\u53d8\u91cf / Variable",
    check_id = "\u89c4\u5219\u7f16\u53f7 / Rule ID",
    evidence = "\u793a\u4f8b / Example",
    severity = "\u4e25\u91cd\u7a0b\u5ea6 / Severity",
    dimension = "\u8d28\u91cf\u7ef4\u5ea6 / Dimension",
    count = "\u6570\u91cf / Count",
    action = "\u5904\u7406\u52a8\u4f5c / Action",
    status = "\u72b6\u6001 / Status",
    message = "\u8bf4\u660e / Message",
    handled = "\u5df2\u5904\u7406 / Handled",
    old_value = "\u539f\u503c / Old value",
    new_value = "\u65b0\u503c / New value",
    method = "\u5904\u7406\u65b9\u6cd5 / Method",
    timestamp = "\u65f6\u95f4 / Timestamp",
    dcc_version = "DCC \u7248\u672c / DCC version",
    ruleset_hash = "\u89c4\u5219\u54c8\u5e0c / Ruleset hash",
    keyfile_hash = "\u5bc6\u94a5\u6587\u4ef6\u54c8\u5e0c / Key-file hash",
    field = "\u5b57\u6bb5 / Field",
    rows = "\u884c / Rows",
    fix = "\u4fee\u590d\u5efa\u8bae / Suggested fix",
    workbook = "\u5de5\u4f5c\u7c3f / Workbook",
    sheet = "\u5de5\u4f5c\u8868 / Sheet",
    row = "\u884c\u53f7 / Row",
    column = "\u5217 / Column",
    cell = "\u5355\u5143\u683c / Cell",
    name = "\u6587\u4ef6\u540d / File name",
    path = "\u8def\u5f84 / Path",
    description = "\u6587\u4ef6\u8bf4\u660e / Description"
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
  review <- utils::head(tables[["\u9700\u8981\u590d\u6838"]], 20L)
  issues <- utils::head(tables[["\u95ee\u9898\u6c47\u603b"]], 20L)
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
    "<h2>\u8fd0\u884c\u6982\u89c8 / Run overview</h2>",
    html_table(tables[["\u8fd0\u884c\u6982\u89c8"]][
      , c("label", "display_value"), drop = FALSE
    ]),
    "<h2>\u95ee\u9898\u6c47\u603b / Findings summary</h2>",
    if (nrow(issues)) html_table(issues) else "<p>\u65e0 / None</p>",
    "<h2>\u9700\u8981\u590d\u6838 / Needs review</h2>",
    if (nrow(review)) html_table(review) else "<p>\u65e0 / None</p>",
    if (workbook) {
      "<p><a href='staff-results.xlsx'>\u5b8c\u6574\u8868\u683c / Full workbook</a></p>"
    } else "",
    "</body></html>"
  )
  writeLines(html, path, useBytes = TRUE)
  invisible(path)
}

write_staff_summary <- function(model, path, language, include_examples) {
  title <- if (language == "zh-CN") {
    "DCC \u8fd0\u884c\u6458\u8981 / Run summary"
  } else "DCC Run Summary / \u8fd0\u884c\u6458\u8981"
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
