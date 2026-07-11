# 数据清洗调研：CRAN 包功能与业界方法论

用途：为 DCC（Data Cleaning Center，调查数据清洗 R 包）的功能设计提供参考。
调研日期：2026-07-11。涵盖 CRAN 现行版本包，及官方统计、田野调查机构与数据工程界的方法论。

> 注：按仓库规范，正式文档应为英文。本文件为内部调研参考，定稿设计文档时请转写为英文。

## 一、按功能类别汇总

### 1. 基础清洗工具

| 包 | 核心功能 |
| --- | --- |
| janitor | `clean_names()` 规范列名；`tabyl()` 频数/交叉表；`get_dupes()` 查重复记录；`remove_empty()` 删空行空列；`excel_numeric_to_date()` 类型修复；管道友好 |
| cleaner | `clean_*()` 系列按类型快速清洗（逻辑、日期、数值、因子、百分比） |
| datawizard / sjmisc | 重编码 `recode_values()`、标准化、居中、变量重命名、行列操作 |

### 2. 规则式校验（validation）

| 包 | 核心功能 |
| --- | --- |
| validate | 声明式校验规则（字段级、记录内、跨记录、跨数据集）；`confront()` 数据与规则对质；结果汇总与可视化；规则可存为独立文件复用 |
| pointblank | 校验流水线（逐步 `col_vals_*()`）；失败率阈值触发警告/报错动作；生成数据质量报告；支持数据库表和 Spark |
| assertr | 管道内断言（`verify()`、`assert()`、`insist()`），失败即中断，适合 ETL 防御式编程 |
| data.validator | 基于 assertr 的批量校验 + HTML 报告 |

### 3. 错误定位与自动修正（调查数据核心）

| 包 | 核心功能 |
| --- | --- |
| errorlocate | 基于 Fellegi–Holt 原则的错误定位：找出需修改的最少（加权）变量集；支持数值线性规则、分类规则、条件规则；`replace_errors()` 置 NA |
| deducorrect | 推断式修正：符号错误、进位/舍入错误、录入调换错误；推断式插补 |
| dcmodify | 声明式"若…则改…"修正规则，规则与代码分离 |
| editrules | 上述功能的前身，已被 validate + errorlocate 取代（设计教训：拆分职责） |

### 4. 缺失值探索与插补

| 包 | 核心功能 |
| --- | --- |
| naniar | 缺失模式可视化（ggplot2）；nabular/shadow 结构记录特殊缺失码（如 -99"拒答"）；`recode_shadow()` |
| VIM | 缺失可视化 + kNN/hotdeck 插补 |
| mice | 多重插补（标准方法） |
| simputation | 统一接口 `impute_*()`，一行代码切换插补模型 |

CRAN 有专门的 [Missing Data Task View](https://cran.r-project.org/view=MissingData)（约 150 个包）。

### 5. 数据诊断与质量报告

| 包 | 核心功能 |
| --- | --- |
| dlookr | 诊断报告：缺失、异常值、唯一值、负值；正态性检验；分箱、偏度处理；一键生成诊断/EDA 报告 |
| dataReporter (dataMaid) | 自动查错报告：疑似异常值、低频/疑似错码因子水平、缺失汇总，输出 PDF/HTML 供人工复核 |
| skimr | 快速摘要统计 `skim()` |

### 6. 标签数据与调查专用

| 包 | 核心功能 |
| --- | --- |
| haven | 读写 SPSS/Stata/SAS；`haven_labelled` 类保留值标签与用户缺失值 |
| labelled | 操作变量标签、值标签、缺失值标签；`recode()` 支持标签向量；`look_for()` 搜索变量 |
| sjlabelled | 标签数据读写与转换（标签↔因子↔数值） |
| questionr | 调查数据交互式重编码/分组界面、加权表、问卷常用统计 |
| expss | SPSS 风格的标签、表格与显著性检验 |
| survey / srvyr | 复杂抽样设计、权重（清洗后分析衔接） |

### 7. 字符串与模糊去重

| 包 | 核心功能 |
| --- | --- |
| stringdist | 多种字符串距离（Levenshtein、Jaro–Winkler 等），近似匹配 |
| refinr | OpenRefine 式聚类合并相近文本值（拼写变体归一） |

### 8. 异常值检测

dlookr（`diagnose_outlier()`、IQR）、outliers（统计检验）、univOutl（官方统计常用的单变量方法）。

## 二、可复用的设计模式

1. **规则与代码分离**（validate、dcmodify）：校验/修正规则写成独立 DSL 文件，可版本管理、可复用、非程序员可读。调查机构最常用此模式。
2. **对质–报告模式**（validate 的 `confront()` → `summary()`/`plot()`）：校验不直接改数据，先产出违规清单供审查。
3. **流水线 + 阈值动作**（pointblank）：逐步校验，按失败率触发 warn/stop/notify。
4. **最小修改原则**（errorlocate 的 Fellegi–Holt）：自动定位错误时改动最少的变量。
5. **特殊缺失码语义**（naniar shadow、haven user-defined NA）：调查数据中"拒答/不适用/跳答"须与真缺失区分——DCC 的关键需求。
6. **清洗留痕**：deducorrect 返回修正日志；可审计性是官方统计包的共同特征。
7. **一键质量报告**（dlookr、dataReporter、data.validator）：HTML/PDF 报告供人工复核。

## 三、业界方法论与原则（CRAN 之外）

### 1. 统计数据清洗五阶段模型（van der Loo & de Jonge，荷兰统计局）

《Statistical Data Cleaning with Applications in R》提出的经典流程，validate/errorlocate 等包即出自此体系：

```text
raw → technically correct → consistent → aggregated → formatted
原始 → 技术正确（类型/编码对）→ 逻辑一致（通过规则）→ 汇总 → 成品
```

核心原则：每阶段的数据分别存档以便复用；阶段间转换各用一个独立脚本；**数据清洗是一项统计操作，必须可复现**。

### 2. Eurostat 校验层级（Validation Levels 0–5）

欧洲统计系统的分层校验框架，由浅入深：

- L0：文件结构、格式、编码表（结构性校验）
- L1：单文件内单元格/记录级校验（类型、取值范围、记录内一致性）
- L2：同数据源跨文件校验（如跨期一致）
- L3–L5：跨数据源、跨机构的一致性与合理性（plausibility）校验

启示：校验规则应按层级组织，先廉价检查后昂贵检查，报告也按层级归类。

### 3. 数据质量维度

通用质量框架（UNICEF DQF、ISO 8000 等）以维度定义"干净"：**完整性**（completeness）、**准确性**（accuracy）、**一致性**（consistency）、**有效性**（validity，取值合法）、**唯一性**（uniqueness，无重复）、**时效性**（currency）。质量报告按维度打分，比笼统的"发现 N 个问题"更可比较、可追踪。

### 4. 田野调查机构实践（World Bank DIME、IPA、J-PAL）

- **高频检查（HFC）**：数据采集期间每日运行的一键式检查——重复访问、样本覆盖（应答与抽样名单核对）、访问时长异常、逻辑跳答违规、访员效应；代码在开始采集前写好。
- **原始数据不可变**：清洗永远输出新数据集，原始数据只读存档。
- **数据、代码、结果分离**，所有删改留有文档（何时、为何、改了什么）。
- **码本驱动清洗**：iecodebook（Stata）用一张码本表批量完成重命名、重编码、打标签、协调多轮数据——声明式、非程序员可维护。
- **去标识化**：清洗流程内置 PII 识别与脱敏步骤，直接影响数据可否共享。

### 5. 数据工程界实践

- **校验即测试**：Great Expectations / dbt tests 把数据校验写成断言套件，随流水线自动运行，失败率超阈值即告警或中断（pointblank 是其 R 对应物）。
- **数据契约**：上下游以 schema + 质量规则为契约，进数据先验约。
- **tidy data 原则**（Wickham）：每列一变量、每行一观测、每表一观测单元——清洗的目标形态。

### 6. DCC 设计准则：精准探测 — 高效执行 — 可审计报告

将业界共同原则映射到公司数据服务特征流程的三个阶段，每条清洗操作都必须完整经过三阶段，形成闭环留痕。

#### 阶段一：精准探测（Detect）—— 只发现，不修改

1. 规则声明式、外置、可版本管理（对标 validate/dcmodify 的规则文件）
2. 检查按 Eurostat 层级组织（结构 → 记录 → 跨记录 → 跨数据集），先廉价后昂贵
3. 探测输出结构化"违规清单"（记录 ID × 规则 ID × 涉及变量 × 严重度），作为下一阶段的唯一输入
4. 按质量六维度归类计分，探测结果可跨轮次、跨项目比较

#### 阶段二：高效执行（Execute）—— 只依探测结果修改，最小干预

1. 校验与修正分离：执行阶段只处理违规清单中的条目，不做临时探测
2. 自动修正遵循最小修改原则（Fellegi–Holt），能推断修正的不插补，能插补的不删除
3. 修正动作本身也是声明式规则（若…则改…），与探测规则同库管理
4. 原始数据只读；执行输出新版本数据集，版本间可 diff

#### 阶段三：可审计报告（Report）—— 每一格的变化都可追溯到规则和证据

1. 逐条修改留痕：记录 ID、变量、原值 → 新值、触发规则、修正方法、执行时间、执行者/版本
2. 报告双层输出：管理层摘要（质量维度得分、修改量统计）+ 审计明细（cell 级修改日志），可复核、可回滚
3. 审计日志本身是机器可读数据（而非仅 PDF），支持"从成品数据任一单元格反查其清洗历史"
4. 整条 探测→执行→报告 流水线一键复现：同样的原始数据 + 同样的规则版本 = 同样的成品与报告

闭环要求：报告中每一条修改必须能对应到探测清单中的一条违规；无探测依据的修改视为流程违规。

## 四、对 DCC 的功能建议（按三阶段组织）

### 精准探测

1. 列名/类型/编码诊断 + 重复记录检测（对标 janitor/dlookr）
2. 声明式校验规则引擎 + 分层违规清单（对标 validate + Eurostat 层级）
3. 逻辑跳答/一致性检查与错误定位（对标 errorlocate，问卷特有）
4. 高频检查（HFC）模块：采集期间日常运行的一键质量检查（对标 ipacheck，CRAN 尚无成熟 R 对应物，**差异化机会**）

### 高效执行

1. 码本驱动的批量重命名/重编码/打标签（对标 iecodebook，同为差异化机会）
2. 标签与特殊缺失码处理（对标 labelled/naniar，调查数据差异化重点）
3. 声明式修正规则 + 推断式修正（对标 dcmodify/deducorrect，最小修改）
4. 插补接口（对标 simputation，统一接口、可插拔）
5. 去标识化辅助（PII 扫描与脱敏）

### 可审计报告

1. cell 级修改日志（机器可读）+ 反查接口：任一单元格 → 其清洗历史
2. 双层质量报告：管理层摘要（质量维度得分）+ 审计明细（对标 dataReporter/pointblank 报告 + DIME 留痕要求）
3. 流水线复现命令：原始数据 + 规则版本 → 一键重建成品与报告

## 五、DCC 核心功能需求清单（公司指定，2026-07-11）

以下功能为 DCC 的基础必备项，按三阶段归位。

### 精准探测：作答质量清洗（v1 核心）

| 功能 | 说明 | CRAN 对标 / 实现要点 |
| --- | --- | --- |
| 人群与得分差异清洗 | 按人群分组检测得分分布异常（组间差异、离群分数） | dlookr 异常值方法 + 分组统计；DIF 思路可参考 difR |
| 陷阱题清理 | 依据陷阱题/注意力检查题的作答剔除无效样本 | careless 包无直接对应，需自研：陷阱题标记 + 判定规则 |
| 作答时间清洗 | 总时长/单题时长过短或异常的作答标记 | careless 领域文献常用；实现为可配置阈值 + 分布法（如中位数比例） |
| 同选项题数过多清洗 | 直线作答（straight-lining）检测 | careless::longstring()、responsePatterns（自相关法） |
| 空题过多清洗 | 缺答率超阈值的样本标记 | naniar 缺失统计 + 阈值规则 |

五项均输出到统一违规清单（样本 ID × 检查项 × 证据值 × 严重度），剔除决定在执行阶段依规则完成，保证可审计。

### 高效执行：清洗后处理

| 功能 | 说明 | 实现要点 |
| --- | --- | --- |
| 答案判分 | 依据答案表（answer key）将清洗后样本的选项判定正误/得分 | 支持单选、多选、部分给分；对标 CTT::score()、mirt 的 key2binary |
| 试卷-题目映射 | 通过"试卷-题目对应表"将不同版本样本卷的题目对齐到总体题表 | 多套卷（multiple forms）→ 主题库（master item bank）的映射连接；对应表为码本式外置文件，声明式管理 |

判分与映射的输入是清洗后数据 + 外置对照表（答案表、对应表），两表纳入版本管理，报告中记录所用版本。

### 性能要求

- 小样本（几十~几千）与大样本（百万级）同一 API，后端自适应
- 实现要点：data.table 作为核心计算后端（百万行内存内可行）；超大数据可选 arrow/duckdb 后端做分块/惰性计算；规则求值向量化，避免逐行循环
- 建立性能基准测试（如 1e4 / 1e6 / 1e7 行）纳入 CI

### 输入层要求

- 文件格式：CSV/TSV（data.table::fread、readr）、Excel（readxl）、SPSS/Stata/SAS（haven，保留标签）、Parquet/Feather（arrow）、JSON
- 编码：自动探测（stringi::stri_enc_detect）+ 显式指定；至少覆盖 UTF-8、GB18030/GBK、BIG5、Latin-1
- 读入即做结构诊断（L0 层校验），输出读取报告（编码、行列数、类型推断结果）

## 参考来源

- <https://cran.r-project.org/web/packages/janitor/index.html>
- <https://cran.r-project.org/package=dlookr>
- <https://cran.r-project.org/web/packages/cleaner/readme/README.html>
- <https://cran.r-project.org/package=validate>（含 [Data Validation Cookbook](https://cran.r-project.org/web/packages/validate/vignettes/cookbook.html)）
- <https://cran.r-project.org/web/packages/pointblank/index.html>
- <https://cran.r-project.org/web/packages/errorlocate/index.html>
- <https://cran.r-project.org/web/packages/editrules/index.html>
- <https://cran.r-project.org/package=naniar>
- <https://cran.r-project.org/web/packages/sjlabelled/index.html>
- <https://cran.r-project.org/web/packages/labelled/labelled.pdf>
- <https://cran.r-project.org/web/views/OfficialStatistics.html>
- <https://cran.r-project.org/view=MissingData>

方法论：

- van der Loo & de Jonge, *Statistical Data Cleaning with Applications in R*；入门版：<https://cran.r-project.org/doc/contrib/de_Jonge+van_der_Loo-Introduction_to_data_cleaning_with_R.pdf>
- Eurostat 校验层级：<https://cros.ec.europa.eu/book-page/validation-levels>；GSBPM 与校验：<https://cros.ec.europa.eu/book-page/validation-and-gsbpm>
- World Bank DIME 数据清洗：<https://dimewiki.worldbank.org/Data_Cleaning>；清洗检查单：<https://dimewiki.worldbank.org/Checklist:_Data_Cleaning>；高频检查：<https://dimewiki.worldbank.org/High_Frequency_Checks>；DIME Analytics Data Handbook 第 5 章：<https://worldbank.github.io/dime-data-handbook/processing.html>
- J-PAL 数据清洗与管理：<https://www.povertyactionlab.org/resource/data-cleaning-and-management>
- UNICEF 数据质量框架：<https://data.unicef.org/wp-content/uploads/2022/01/Data-Quality-Framework.pdf>

作答质量检测：

- careless（longstring、马氏距离、个体内变异等无效作答指标）：<https://cran.r-project.org/web/packages/careless/index.html>
- responsePatterns（自相关法检测规律性作答）：<https://cran.r-project.org/web/packages/responsePatterns/responsePatterns.pdf>
