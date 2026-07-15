test_that("staff reports preserve normalized totals and exact sheets", {
  out <- withr::local_tempdir()
  model <- report_model_fixture()
  files <- dcc_report_staff(model, out)

  expect_setequal(
    basename(files),
    c("staff-results.xlsx", "staff-report.html", "run-summary.txt")
  )
  workbook <- file.path(out, "staff-results.xlsx")
  wb <- openxlsx2::wb_load(workbook)
  expect_identical(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("运行概览", "导入检查", "阻断错误", "问题汇总", "需要复核",
      "已应用更改", "排除记录", "输出文件说明")
  )
  overview <- openxlsx2::wb_to_df(workbook, sheet = "运行概览")
  expect_equal(
    overview$value[overview$key == "findings_total"],
    model$summaries$findings_total
  )
  expect_equal(
    overview$value[overview$key == "excluded_total"],
    model$summaries$excluded_total
  )
})

test_that("staff reports redact examples by default", {
  out <- withr::local_tempdir()
  secret <- "ID-123-sensitive"
  files <- dcc_report_staff(report_model_fixture(secret), out)
  html <- readLines(files[basename(files) == "staff-report.html"], warn = FALSE)
  workbook_text <- unlist(lapply(
    c("问题汇总", "需要复核", "已应用更改", "排除记录"),
    function(sheet) unlist(openxlsx2::wb_to_df(
      files[basename(files) == "staff-results.xlsx"], sheet = sheet
    ), use.names = FALSE)
  ), use.names = FALSE)

  expect_false(any(grepl(secret, html, fixed = TRUE)))
  expect_false(any(grepl(secret, workbook_text, fixed = TRUE)))
  expect_true(any(grepl("REDACTED", c(html, workbook_text), fixed = TRUE)))
})

test_that("staff reports disclose examples only after explicit opt-in", {
  out <- withr::local_tempdir()
  secret <- "ID-123-sensitive"
  files <- dcc_report_staff(
    report_model_fixture(secret), out, formats = "html",
    include_examples = TRUE
  )
  html <- readLines(files[basename(files) == "staff-report.html"], warn = FALSE)

  expect_true(any(grepl(secret, html, fixed = TRUE)))
  expect_true(any(grepl("examples_included", html, fixed = TRUE)))
})

test_that("staff workbook row limits fail before truncation", {
  expect_error(
    staff_preflight_rows(c(`需要复核` = 1048576L)),
    "Excel row limit", class = "dcc_report_error"
  )
  expect_silent(staff_preflight_rows(c(`需要复核` = 1048575L)))
})

test_that("staff renderer validates formats and output collisions", {
  model <- report_model_fixture()
  expect_error(
    dcc_report_staff(model, withr::local_tempdir(), formats = "pdf"),
    class = "dcc_report_error"
  )
  out <- withr::local_tempdir()
  writeLines("keep", file.path(out, "staff-report.html"))
  expect_error(dcc_report_staff(model, out), class = "dcc_report_error")
  expect_identical(readLines(file.path(out, "staff-report.html")), "keep")
})
