# DCC 严格 Excel 工作流快速指南

本入口面向不熟悉统计学和编程的调查工作人员。只编辑黄色单元格；不要增加、删除、改名或调整工作表和列。DCC 会拒绝结构变化，而不会猜测含义。

## 1. 安装并创建模板

```r
remotes::install_github("weiandata/DCC", dependencies = TRUE)
library(DCC)
dcc_template("DCC-cleaning-plan.xlsx")
```

DCC 会一次安装正式支持格式的读取依赖。模板包含 project、source、columns、values、missing、multiselect、rules、actions、outputs 九个受保护工作表。保护没有密码，只用于避免误改结构。

## 2. 填写 Excel

在 source 填写文件路径、明确格式和文本编码；在 columns 逐列声明原始列名、标准列名、类型、用途和是否必填。规则参数和动作参数是 JSON；无参数时填写 `{}`。使用单元格下拉列表，不要改英文机器表头。

## 3. 先检查

```r
check <- dcc_check(
  "responses.csv",
  "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-check"
)
```

查看 `validation.xlsx`、`preview-findings.xlsx`、`staff-report.html` 和 `run-summary.txt`。检查不会执行动作，也不会写清洗数据。遇到代码时运行 `dcc_help("PLAN_COLUMN_TYPE")` 查看中文解释和修复办法。

## 4. 预览和执行

```r
preview <- dcc_run(
  "responses.csv",
  plan = "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-preview"
)

result <- dcc_run(
  "responses.csv",
  plan = "DCC-cleaning-plan.xlsx",
  output_dir = "dcc-result",
  mode = "execute"
)
```

执行结果包含清洗数据、发现、审计日志、HTML 报告、manifest 和摘要；PDF 不是固定输出。DCC 从不覆盖已有输出目录，也从不修改原始数据文件。

## 专业统计人员与 AI Agent

专业人员可以用 `dcc_read_plan()`、`dcc_validate_plan()`、`dcc_import()` 和原有低层函数检查或扩展流程。Agent 应先查询 `dcc_capabilities()` 和 `dcc_schema("plan")`，使用 JSON 或严格 Excel 计划，先 `dcc_check()`/preview，再在明确授权后 execute；不要解析自然语言错误消息，应使用稳定代码、错误类和 JSON Pointer/Excel 单元格坐标。

