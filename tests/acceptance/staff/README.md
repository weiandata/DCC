# 工作人员可用性验收

本套件面向不了解统计学和编程的普通调查工作人员。参与者只编辑 DCC
严格 Excel 项目模板，并运行文档给出的短 R 命令。测试必须使用合成调查
数据；不得让参与者修改 R 代码，也不得把输出写回原始数据文件。

运行 `Rscript tools/run-acceptance.R --audience=staff --mode=synthetic` 只会
验证场景契约并复制一份主持人记录表。该结果不是人类可用性通过证据。
发布证据必须包含至少五名参与者的签名记录、每个场景的起止时间、错误与
恢复过程、preview/execute 区分题、原始文件哈希核对以及完整 SUS 问卷。

通过标准由 `scenarios.yml` 和 `docs/acceptance/scoring.md` 唯一定义。

