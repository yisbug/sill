# 本仓库是 fork：合并上游时的规则

本仓库是 Saffsanity/sill（远端 `upstream`）的 fork（远端 `origin`）。只在本 fork 里有的改动记在 `docs/fork-changes.md`。

- **每次把上游合进来**（`git merge upstream/main`，或任何带入上游提交的操作）：先读 `docs/fork-changes.md`，按其中"合并上游的步骤"做；冲突解决完、提交合并之前运行 `Scripts/fork-check.py --against <合并前的提交>`，标记和译文两部分必须通过，"可能丢失的行"逐个文件看过；被覆盖的改动补回来再提交。汇报里写出脚本的实际输出结论。
- **新增只在本 fork 有的改动**：在同一个提交里更新 `docs/fork-changes.md`（加一项或并入已有项，写上 `fork-check` 标记）。
- fork 的说明只写在 fork 自己的文件里（`docs/fork-changes.md`、`docs/voice-and-immersive-plan.md`、`docs/l10n-glossary.md`、本文件）；不改上游的 `CLAUDE.md`、`README.md`、`docs/DEVELOPMENT.md`，免得每次合并都冲突。
