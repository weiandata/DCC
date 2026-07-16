# DCC 1.2.0 工作人员完整测试脚本
#
# 第一次运行请保持 FALSE。确认检查和预览结果后，如主持人批准执行，
# 将下一行改为 TRUE，并重新运行本脚本。
AUTHORIZE_EXECUTION <- FALSE

required_version <- "1.2.0"

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    return(sub("^--file=", "", file_arg[[1L]]))
  }
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    candidate <- frames[[i]]$ofile
    if (!is.null(candidate) && length(candidate) == 1L) return(candidate)
  }
  stop("无法确定脚本位置。请在 RStudio 中使用 Source 运行本文件。")
}

kit_dir <- dirname(normalizePath(script_path(), mustWork = TRUE))
old_wd <- setwd(kit_dir)
on.exit(setwd(old_wd), add = TRUE)

local_library <- file.path(kit_dir, "R-library")
if (!dir.exists(local_library) &&
    !dir.create(local_library, recursive = TRUE)) {
  stop("无法创建本地 R 包目录：", local_library)
}
.libPaths(c(local_library, .libPaths()))

file_repository_url <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- if (.Platform$OS.type == "windows") "file:///" else "file://"
  paste0(prefix, utils::URLencode(path, reserved = FALSE))
}

installed_dcc_version <- function() {
  if (!requireNamespace("DCC", quietly = TRUE)) return(NA_character_)
  as.character(utils::packageVersion("DCC"))
}

if (!identical(installed_dcc_version(), required_version)) {
  repository <- file.path(kit_dir, "offline-install", "repository")
  if (!dir.exists(repository)) {
    stop(
      "未找到离线安装仓库：", repository,
      "\n请确认完整测试文件夹没有缺失 offline-install 子目录。"
    )
  }
  message("正在从测试文件夹安装 DCC 及其正式输入格式依赖……")
  utils::install.packages(
    "DCC",
    lib = local_library,
    repos = file_repository_url(repository),
    dependencies = c("Depends", "Imports", "LinkingTo"),
    type = "source"
  )
}

if (!identical(installed_dcc_version(), required_version)) {
  stop("DCC 安装后版本不是 ", required_version, "。")
}
suppressPackageStartupMessages(library(DCC))

data_file <- file.path(kit_dir, "project", "responses.csv")
plan_file <- file.path(kit_dir, "project", "DCC-cleaning-plan.xlsx")
if (!file.exists(data_file) || !file.exists(plan_file)) {
  stop("project 文件夹缺少 responses.csv 或 DCC-cleaning-plan.xlsx。")
}

timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
session_dir <- file.path(kit_dir, paste0("测试输出-", timestamp))
suffix <- 1L
while (dir.exists(session_dir)) {
  session_dir <- file.path(
    kit_dir, paste0("测试输出-", timestamp, "-", suffix)
  )
  suffix <- suffix + 1L
}
if (!dir.create(session_dir, recursive = TRUE)) {
  stop("无法创建测试输出目录：", session_dir)
}

raw_hash_before <- unname(as.character(tools::sha256sum(data_file)))
log_file <- file.path(session_dir, "运行日志.txt")
summary_file <- file.path(session_dir, "测试结果摘要.txt")

run_test <- function() {
  message("第 1 步：检查严格 Excel 计划和合成数据……")
  check <- DCC::dcc_check(
    data_file,
    plan_file,
    output_dir = file.path(session_dir, "01-检查")
  )

  message("第 2 步：生成预览；此步骤不会执行清洗动作……")
  preview <- DCC::dcc_run(
    data_file,
    plan = plan_file,
    output_dir = file.path(session_dir, "02-预览"),
    mode = "preview"
  )

  execution <- NULL
  if (isTRUE(AUTHORIZE_EXECUTION)) {
    message("第 3 步：已获得明确授权，执行并写入新的输出目录……")
    execution <- DCC::dcc_run(
      data_file,
      plan = plan_file,
      output_dir = file.path(session_dir, "03-执行结果"),
      mode = "execute"
    )
  } else {
    message(
      "第 3 步：未执行。请先检查 01-检查 和 02-预览；",
      "主持人批准后再把 AUTHORIZE_EXECUTION 改为 TRUE。"
    )
  }

  raw_hash_after <- unname(as.character(tools::sha256sum(data_file)))
  if (!identical(raw_hash_before, raw_hash_after)) {
    stop("原始合成数据文件哈希发生变化；请立即停止测试并保留现场。")
  }

  lines <- c(
    paste0("DCC 版本: ", as.character(utils::packageVersion("DCC"))),
    paste0("测试时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("测试目录: ", normalizePath(session_dir, winslash = "/")),
    paste0("检查状态: ", check$status),
    paste0("预览模式: ", preview$mode),
    paste0(
      "执行状态: ",
      if (is.null(execution)) "未授权、未执行" else "已授权并完成"
    ),
    paste0("原始文件 SHA-256: ", raw_hash_after),
    "原始文件是否保持不变: 是",
    "",
    "下一步：打开各输出目录中的 run-summary.txt、validation.xlsx、",
    "preview-findings.xlsx 和 staff 报告，并在工作人员验收工作簿中记录结果。"
  )
  writeLines(lines, summary_file, useBytes = TRUE)
  invisible(list(check = check, preview = preview, execution = execution))
}

result <- tryCatch(
  {
    sink(log_file, split = TRUE)
    on.exit(sink(), add = TRUE)
    run_test()
  },
  error = function(e) {
    writeLines(
      c("DCC 工作人员测试失败：", conditionMessage(e)),
      file.path(session_dir, "错误说明.txt"),
      useBytes = TRUE
    )
    stop(e)
  }
)

message("\n测试脚本运行完成。")
message("请打开：", summary_file)
message("工作人员记录表：",
        file.path(kit_dir, "DCC-1.2.0-staff-acceptance.xlsx"))
