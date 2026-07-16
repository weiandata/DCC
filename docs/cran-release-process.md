# DCC 1.2.0 CRAN 发布流程

本文档说明如何从一个已冻结的 DCC 提交生成、验证并提交 CRAN 源码包。
最终上传物必须是 `R CMD build` 生成的 `DCC_1.2.0.tar.gz`，并且必须与
GitHub 全绿提交完全对应。

CRAN 的权威要求以以下官方文档为准：

- [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html)
- [CRAN submission form](https://cran.r-project.org/submit.html)
- [CRAN submission checklist](https://cran.r-project.org/web/packages/submission_checklist.html)
- [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html)

## 1. 发布权限和环境

发布人需要：

- 能接收 `DESCRIPTION` 中维护者邮箱
  `makunxiang@weiandata.com` 的邮件；
- 对 `weiandata/DCC` GitHub 仓库拥有推送权限；
- 已安装当前 R release 或 R-patched；
- 能通过 GitHub Actions 使用 R-devel；
- 已安装 DCC 的全部 `Imports`、`Suggests` 和发布工具依赖；
- 能访问 CRAN 提交页面和确认邮件中的链接。

检查本地工具：

```sh
R --version
git --version
gh auth status
```

成功条件：

- R 版本是当前 release、R-patched 或更新版本；
- Git 可用；
- `gh auth status` 显示对 `github.com` 的有效登录。

如果 `gh` 登录失效：

```sh
gh auth login -h github.com
```

保留证据：终端版本信息和 GitHub 登录成功状态。不得把访问令牌写入仓库、
日志或发布证据。

## 2. 冻结候选版本

确认当前目录是 DCC 仓库根目录：

```sh
test -f DESCRIPTION
test -f NAMESPACE
test -d R
```

成功条件：三个命令均退出 0。

检查版本和维护者：

```sh
Rscript -e 'd <- read.dcf("DESCRIPTION");
stopifnot(d[1, "Package"] == "DCC");
stopifnot(d[1, "Version"] == "1.2.0");
cat(d[1, "Package"], d[1, "Version"], "\n");
cat(d[1, "Authors@R"], "\n")'
```

成功条件：

- 输出包名 `DCC`；
- 输出版本 `1.2.0`；
- `Authors@R` 中只有一个 `cre`，并且邮箱可接收 CRAN 邮件。

检查候选提交：

```sh
git status --short --branch
git rev-parse HEAD
git log -1 --format='%H%n%ad%n%s' --date=iso-strict
```

成功条件：

- 发布所需的源码和文档改动已经提交；
- 没有未知的已跟踪文件修改；
- 记录完整 40 位提交 SHA。

生成的 `DCC.Rcheck/`、`DCC_1.2.0.tar.gz` 和 `artifacts/` 可以是未跟踪
文件，但最终包必须在 GitHub 全绿后重新构建。

## 3. 检查包元数据和 CRAN 政策

人工检查以下文件：

- `DESCRIPTION`
- `NAMESPACE`
- `NEWS.md`
- `cran-comments.md`
- `inst/COPYRIGHTS`
- `LICENSE` 或 `LICENSE.md` 的发布排除规则

重点确认：

- 标题使用 title case，且没有句号结尾；
- Description 清楚说明包的用途，不包含营销性或无法验证的声明；
- 维护者是自然人且邮箱有效；
- License 与所有第三方组件的版权信息一致；
- `URL` 和 `BugReports` 可以访问；
- 所有强依赖来自 CRAN 或 Bioconductor；
- 安装和加载阶段不下载软件或数据；
- 测试、示例和 vignette 不写入用户主目录；
- 源码 tarball 不包含内部离线仓库、验收记录或用户数据。

运行依赖合同检查：

```sh
Rscript tools/verify-dependencies.R
```

成功条件：输出依赖验证通过，且未发现未声明调用或运行时安装器。

保留证据：命令输出和最终 `DESCRIPTION`。

## 4. 运行发布测试

运行一次完整发布测试：

```sh
Rscript tools/run-release-tests.R \
  --runs=1 \
  --output=artifacts/release-tests-final.json
```

成功条件：JSON 中 `status` 为 `pass`，并且 failures、warnings、skips
全部为 0。

重复运行 property、fault 和 backward 套件：

```sh
Rscript tools/run-release-tests.R \
  '--filter=property|fault|backward' \
  --runs=5 \
  --output=artifacts/property-fault-final.json
```

成功条件：连续五次运行均无 failure、warning 和 skip。

保留：

- `artifacts/release-tests-final.json`
- `artifacts/property-fault-final.json`

任何 skip 都是发布阻断项，不能把缺少依赖或平台能力描述为测试通过。

## 5. 运行百万行 benchmark

安装当前源码：

```sh
R CMD INSTALL .
```

成功条件：安装结束时输出 `* DONE (DCC)`。

生成三次百万行证据：

```sh
Rscript tools/benchmarks/benchmark.R \
  --rows=1000000 \
  --runs=3 \
  --output=artifacts/benchmark-current.json
```

成功条件：

- 三次运行均完成；
- 每个 stage 的 correctness 为 `true`；
- 输出 `BENCHMARK CAPTURE: PASS`。

运行内存硬门禁：

```sh
Rscript tools/benchmarks/memory.R \
  --input=artifacts/benchmark-current.json \
  --output=artifacts/memory-current.json
```

成功条件：输出 `MEMORY: PASS`。

在稳定、完全同类的硬件上运行 strict 比较：

```sh
Rscript tools/check-benchmarks.R \
  --current=artifacts/benchmark-current.json \
  --baseline=tools/benchmarks/baseline.json
```

成功条件：输出 `BENCHMARK: PASS`。

GitHub 共享 runner 使用 hosted advisory 模式：

```sh
Rscript tools/check-benchmarks.R \
  --current=artifacts/benchmark-current.json \
  --baseline=tools/benchmarks/baseline.json \
  --strict-relative=false
```

允许的成功输出：

- `BENCHMARK: PASS`
- `BENCHMARK: PASS WITH ADVISORIES`

`PASS WITH ADVISORIES` 只允许相对耗时变化超过 20%。以下情况在任何模式
下都必须失败：

- 当前证据或基线合同无效；
- platform 或 CPU class 不匹配；
- stage 缺失；
- 运行少于三次；
- correctness 失败；
- 内存回归超过限制；
- execution 中位数超过 45 秒；
- 时间或内存数据不是有限数值。

保留：

- `artifacts/benchmark-current.json`
- `artifacts/memory-current.json`
- `tools/benchmarks/baseline.json`

## 6. 构建 CRAN 源码包

先检查 Git diff：

```sh
git diff --check
```

成功条件：无输出并退出 0。

构建源码包：

```sh
R CMD build --no-manual .
```

成功条件：

- 输出 `* building 'DCC_1.2.0.tar.gz'`；
- 当前目录生成 `DCC_1.2.0.tar.gz`；
- 包名符合 `PACKAGE_VERSION.tar.gz`。

检查大小和内容：

```sh
ls -lh DCC_1.2.0.tar.gz
tar -tzf DCC_1.2.0.tar.gz
```

成功条件：

- 源码包显著低于 CRAN 建议的 10 MB；
- 包根目录只有一个 `DCC/`；
- 不包含 `.git/`、`.github/`、`artifacts/`、`DCC.Rcheck/`、
  `cran-comments.md`、内部离线仓库或验收原始记录。

保留：本轮构建的 `DCC_1.2.0.tar.gz`。

## 7. 对实际 tarball 运行 CRAN 检查

必须检查将要上传的 tarball，而不是只检查源码目录：

```sh
R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz
```

成功条件：

- 0 ERROR；
- 0 WARNING；
- 0 actionable NOTE；
- 测试无 failure、warning 和 skip；
- 唯一允许的 NOTE 是首次提交产生的 `New submission`。

分类检查日志：

```sh
Rscript tools/classify-r-check.R \
  --log=DCC.Rcheck \
  --output=artifacts/release/r-check-final.json
```

成功条件：输出 `R CHECK EVIDENCE: PASS`。

检查分类结果：

```sh
jq . artifacts/release/r-check-final.json
```

首次提交的允许状态是：

```json
{
  "status": "pass",
  "errors": 0,
  "warnings": 0,
  "notes": 1,
  "actionable_notes": 0,
  "allowed_notes": ["cran_new_submission"],
  "test_failures": 0,
  "test_warnings": 0,
  "test_skips": 0
}
```

任何其他 NOTE、NOTE 数量不一致或 incoming NOTE 中出现额外文本，都必须
修复后重新构建和检查。

保留：

- `DCC.Rcheck/00check.log`
- `artifacts/release/r-check-final.json`
- 被检查的 `DCC_1.2.0.tar.gz`

## 8. 检查 GitHub 发布矩阵

推送候选提交：

```sh
git push origin main
```

必须等待以下检查全部完成：

| Workflow | 必须成功的任务 |
| --- | --- |
| Release candidate R checks | Ubuntu R-devel、Ubuntu release、macOS release、Windows release |
| Clean complete installation | Ubuntu、macOS、Windows |
| Format and encoding matrix | Ubuntu R-devel、Ubuntu release、macOS release、Windows release |
| Release coverage gate | overall 90%、critical areas 95% |
| Repository checks | Markdown 和链接检查 |
| Performance and memory gate | 百万行正确性、内存和执行预算 |

检查当前提交：

```sh
gh run list --branch main --limit 20
gh pr checks
```

如果当前分支没有 PR，使用：

```sh
gh run list --commit "$(git rev-parse HEAD)" --limit 20
```

成功条件：

- 当前提交没有 failure；
- 没有 queued 或 in-progress；
- 四个 `--as-cran` 矩阵任务全部成功。

GitHub 网页：

- [DCC Actions](https://github.com/weiandata/DCC/actions)

保留：每个 workflow 的 run URL、commit SHA 和 JSON artifact 标识。

## 9. 可选的 CRAN 外部预检查

CRAN policy 建议无法直接使用 Windows 的维护者使用
[win-builder](https://win-builder.r-project.org/) 检查最终 tarball。DCC
已有 GitHub Windows 检查，但首次提交仍建议把完全相同的
`DCC_1.2.0.tar.gz` 发送到 win-builder。

如果 CRAN 或本地检查提示 macOS ARM64 问题，使用
[macbuilder](https://mac.r-project.org/macbuilder/submit.html) 检查相同
tarball。

成功条件：外部服务没有新的 ERROR、WARNING 或 actionable NOTE。

保留：服务返回的检查邮件和日志。

## 10. 生成最终上传包和校验和

GitHub 全绿后，从相同提交重新构建：

```sh
git rev-parse HEAD
git rev-parse origin/main
R CMD build --no-manual .
R CMD check --as-cran --no-manual DCC_1.2.0.tar.gz
```

成功条件：

- 本地和远端 SHA 完全一致；
- 重建后的 tarball 再次通过 CRAN 检查。

保存最终文件：

```sh
mkdir -p artifacts/cran
cp DCC_1.2.0.tar.gz artifacts/cran/DCC_1.2.0.tar.gz
shasum -a 256 artifacts/cran/DCC_1.2.0.tar.gz \
  > artifacts/cran/DCC_1.2.0.sha256
```

验证校验和：

```sh
shasum -a 256 -c artifacts/cran/DCC_1.2.0.sha256
```

成功条件：输出 `artifacts/cran/DCC_1.2.0.tar.gz: OK`。

最终保留：

- `artifacts/cran/DCC_1.2.0.tar.gz`
- `artifacts/cran/DCC_1.2.0.sha256`
- `artifacts/cran/release-metadata.json`
- `artifacts/cran/r-check-final.json`
- GitHub 全绿 run URL

## 11. 填写 CRAN 提交说明

提交前打开 `cran-comments.md`，只陈述已经有证据支持的结果。

首次提交建议包含：

- 包版本：DCC 1.2.0；
- 测试平台：Ubuntu R-devel、Ubuntu release、macOS release、Windows
  release；
- 0 ERROR、0 WARNING；
- 唯一 NOTE 是 `New submission`；
- 说明包不在安装时下载依赖；
- 说明 PDF 是可选输出而不是固定功能；
- 如有外部服务限制，准确说明限制，不把未运行的检查写为通过。

不要在提交说明中粘贴冗长日志。保留简短、可核验的事实。

## 12. 上传到 CRAN

打开 [CRAN submission form](https://cran.r-project.org/submit.html)。

填写：

- Package source：最终的 `artifacts/cran/DCC_1.2.0.tar.gz`；
- Maintainer email：`makunxiang@weiandata.com`；
- Optional comment：使用 `cran-comments.md` 中的简短说明。

提交后：

1. 检查维护者邮箱；
2. 打开 CRAN confirmation 邮件中的确认链接；
3. 确认页面显示提交已接受；
4. 可在 [CRAN incoming](https://cran.r-project.org/incoming/) 检查是否收到。

CRAN policy 明确要求使用网页表单上传源码 tarball，不要把包作为邮件附件
发送。

## 13. 等待 incoming checks

提交处于 pending 时：

- 不要重复提交同一包；
- 不要修改或覆盖已提交 tarball 的本地证据；
- 保存 CRAN 自动检查邮件；
- 只在 CRAN 要求时回复或重新提交。

如果收到自动检查结果：

1. 对照 `DCC.Rcheck/00check.log`；
2. 判断是否可以本地或 CI 复现；
3. 修复根因并增加回归测试；
4. 增加版本号；
5. 重新构建全部证据；
6. 使用提交表单的 Optional comment 说明每条反馈如何解决。

CRAN policy 建议每次重新提交增加版本号，以免不同 tarball 使用相同版本
造成混淆。

## 14. CRAN 接受后的操作

等待 CRAN 包页面出现：

- `https://cran.r-project.org/package=DCC`
- `https://cran.r-project.org/web/checks/check_results_DCC.html`

CRAN 检查页面可能需要至少 48 小时才完全更新。确认页面和检查结果稳定后
再进行后续操作。

创建版本标签：

```sh
git tag -a v1.2.0 -m "DCC 1.2.0"
git push origin v1.2.0
```

创建 GitHub Release 时附上：

- CRAN 链接；
- `NEWS.md` 的 1.2.0 摘要；
- 最终源码包 SHA-256；
- 对应 commit SHA。

不要把内部离线仓库或包含第三方源码的内部 bundle 当作 CRAN 源码包上传。

## 15. 回滚和重新发布规则

如果 GitHub 检查失败：

- 不提交 CRAN；
- 修复后从新 commit 重建 tarball；
- 旧 tarball 标记为作废，不再上传。

如果本地 `R CMD check --as-cran` 出现新问题：

- 不复用旧 tarball；
- 修复、提交、重新运行全部检查；
- 重建 SHA-256 和 release metadata。

如果 CRAN 已接受后发现严重问题：

- 立即评估是否需要请求归档；
- 使用新版本修复，不修改已经发布的 1.2.0 tarball；
- 与 CRAN 的已发布包沟通使用 `CRAN@R-project.org`，提交问题使用
  `CRAN-submissions@R-project.org`；
- 所有邮件使用纯文本，避免 HTML。

## 16. 发布完成定义

DCC 1.2.0 只有同时满足以下条件才算完成：

- 本地完整发布测试通过；
- 本地最终 tarball 的 `R CMD check --as-cran` 通过；
- 只有 `cran_new_submission` NOTE；
- GitHub 当前提交所有检查全绿；
- 最终 tarball、SHA-256、check evidence 和 commit metadata 一致；
- CRAN confirmation 已完成；
- CRAN 包页面和检查页面出现且无新问题；
- Git tag 和 GitHub Release 指向同一源码提交。
