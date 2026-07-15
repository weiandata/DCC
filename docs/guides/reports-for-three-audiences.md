# 一次运行，三类报告

DCC 先从一次清洗结果创建一个经过验证的 `dcc_report_model`，再从这个
模型生成三类报告。渲染器不会重新计算清洗统计，因此三类报告中的
`run_id`、行数、发现数、处理数、排除数、对账结果和数据哈希必须一致。

## 调查工作人员

工作人员只需编辑严格模板的黄色单元格。建议在
`输出设置 / Outputs` 中保留：

| key | 建议值 | 作用 |
|---|---:|---|
| `report_language` | `zh-CN` | 中文主标签并保留英文对照 |
| `include_staff_report` | `TRUE` | 生成 `staff/` |
| `include_statistical_report` | `TRUE` | 生成 `statistical/` |
| `include_machine_report` | `TRUE` | 生成 `machine/` |
| `statistical_table_format` | `parquet` 或 `csv` | 完整统计表格式 |
| `include_sensitive_examples` | `FALSE` | 默认隐藏原值、新值和证据示例 |

运行只需要：

```r
library(DCC)
dcc_check("responses.csv", "DCC-cleaning-plan.xlsx", "dcc-check")
dcc_run("responses.csv", plan = "DCC-cleaning-plan.xlsx",
        output_dir = "dcc-preview")
```

先查看预览，再换一个新目录并显式设置 `mode = "execute"`。工作人员主要
阅读 `staff/staff-results.xlsx`、`staff/staff-report.html` 和
`staff/run-summary.txt`。工作簿固定包含运行概览、导入检查、阻断错误、
问题汇总、需要复核、已应用更改、排除记录和输出文件说明。默认报告保留
计数和记录定位信息，但把证据及变更前后值显示为 `[REDACTED]`。

## 专业统计人员

统计人员可以复用严格 Excel 计划，也可以使用通过同一 Schema 验证的 JSON
计划。`statistical/` 包含完整的 findings、audit log、reconciliation、
missingness、distributions、types、scoring 和 mapping 表，不抽样、不静默
截断；同时包含方法说明、参数、来源信息及 SHA-256 产物清单。

需要直接控制时：

```r
model <- dcc_report_model(result, run)
dcc_report_statistical(model, "statistical", table_format = "parquet")
```

完整统计产物可能包含敏感的逐行数据，应按项目数据权限保存和分享。

## AI Agent

Agent 应先读取 `dcc_capabilities()` 和所需的 `dcc_schema()`，不得猜测字段或
修补未通过验证的计划。`machine/` 的路径稳定，包含：

- `run.json`、`validation.json`、`summary.json`、`provenance.json`
- `findings.jsonl`、`audit-log.jsonl`、`reconciliation.jsonl`
- `manifest.json` 和运行时使用的 `schemas/`

```r
dcc_validate_json("machine/summary.json", "summary")
dcc_validate_jsonl("machine/findings.jsonl", "finding")
summary <- dcc_result_summary(result, detail = "compact")
```

紧凑摘要最多返回 20 条按稳定规则排序的发现，不含原始 evidence，并给出
稳定的 `next_actions` 代码。机器完整包仍可能含敏感逐行数据，不能当成面向
工作人员的脱敏报告。

## 如何交叉核对

同一次 `dcc_run()` 的以下位置应相等：

| 内容 | staff | statistical | machine |
|---|---|---|---|
| 运行编号 | `运行概览` 的 `run_id` | `parameters.json` 的 `run.run_id` | `summary.json` 的 `run_id` |
| 汇总计数 | `运行概览` | `parameters.json` 的 `counts` | `summary.json` 的 `counts` |
| 数据哈希 | `运行概览` | `parameters.json` 的 `hashes` | `summary.json` 的 `hashes` |
| 完整发现 | `问题汇总` 是聚合视图 | `findings.*` | `findings.jsonl` |
| 完整对账 | 面向复核的视图 | `reconciliation.*` | `reconciliation.jsonl` |

顶层 `run-manifest.json` 也记录同一 run ID、计数、哈希以及每个渲染器的
`success`、`failed` 或 `skipped` 状态。渲染器失败时，DCC 发布带
`.partial-<run_id>` 后缀的诊断目录并保留清洗数据、审计日志和清单，不把
部分成功误报为完整成功。

PDF 是可选的后续转换格式，不是 DCC 基础报告合同，也不会默认生成。
