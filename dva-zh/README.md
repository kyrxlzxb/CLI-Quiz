# DVA-C02 中文 CLI

双击 `quiz.cmd`，或在 PowerShell 中运行：

```powershell
.\quiz.ps1
```

本文件夹可单独复制使用，不依赖上级目录，也不需要联网或安装 Node.js。

- 551 条中文题干，选项保持原英文，保留 22 张配图。
- 输入题号、范围（如 `403-551`）或 `all` 开始练习。多选用逗号分隔（如 `B,C`），`q` 退出。
- 答对显示结果后继续；答错显示正确答案及现有中文核查解析，并记录到本文件夹的 `mistakes-dva.jsonl`。
- 10 道信息不足题先按回车查看中文参考解析，再用 `y` / `n` 自评，不自动判分。结果记录到 `reviews-dva.jsonl`，与英文版记录分开。
- 图片题输入 `i`，在默认图片查看器打开本地配图后返回终端答题。
- 551 是来源记录数，包含原来源重复题。原题条件矛盾和缺失内容仍保留，不通过翻译猜补。

题库与译文来自已核查 PWA 提交 `f39f654`。英文原题干保存在 `question_text_original`，选项、答案、核查说明及自评标记未修改。现有解析可能含 AWS 产品名、代码、官方文档链接等英文内容。

开发维护（需要 Node.js，且从完整仓库重建）：

```powershell
node dva-zh/build.cjs ..\aws-quiz-pwa-offline
node --test dva-zh/test.cjs
```
