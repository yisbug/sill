**合入上游 0.6.2（2026-11-18，fork yisbug/sill 的分支 `claude/lucid-thompson-f514ca`，从 fork 的 main `4f80231` 出发，合入 `upstream/main` 的 `4e00c80`，分叉点 `f224323`，上游 308 个提交）。** 本文件是 fork 自己的记录；fork 相对上游的改动清单和合并步骤在 `docs/fork-changes.md`。

- 合并提交 `a32de106`（`git merge upstream/main`，不 rebase）。18 个文件冲突，两边功能都保留，逐项取舍写在该提交的说明里。之后合入 `origin/zh-hans` 的清单与覆盖检查（`33eb5eb3`），清单同步到 0.6.2（`aa028151`）。
- 上游这期间加入：一键更新与自动更新（`AppUpdater`、`UpdateInstaller`、`UpdateInstallPolicy`、`UpdateAutoPolicy`、`UpdateManifest`）、全屏（`FullScreen`、`FullScreenPolicy`、`RevealEdgePan`）、画中画、多显示器桌面（kind 47 `nextDisplay`、`DesktopDisplays`）、离开控制台时的只读视图（off-console view）、经中继的外出判定、版本标签、设备空闲规则、检查目录按文件夹自述（`Tests/checks/<名>/README.md`、`mutant-checks.py`、`repo-rules`）、步骤文件（`docs/steps`）。
- 协议：上游的种类号用到 47，fork 的语音输入仍是 100–102，没有冲突。`Hello` 同时带 `languages`（fork）与 `offConsoleView`（上游）；`WindowList` 同时带 `voice` 与 `offConsoleView`。
- Xcode 26.6（没有 iOS 27.1 SDK）下要改的三处：`StreamScreen.body` 的修饰链拆成 `screen`、`wired`、`body` 三段；`Scripts/asc.swift` 的 `findBuild` 里局部量改名（Swift 6.3 报 circular reference）；`Tests/checks/desktop-displays/main.swift` 两个闭包写明类型。上游这次没有带回 iOS 27.1 专属接口。
- 上游的全屏与 fork 的顶栏折叠、隐藏状态栏叠加：`landscape` 里外层是全屏（`hidden`，整套界面从左边缘滑出），内层是顶栏折叠（`barHidden`，向上收起）；全屏时不画折叠入口；串流界面仍一律隐藏状态栏，另加上游的 `FullScreenSystem`。语音悬浮球在全屏时仍显示。
- `project.pbxproj`：fork 的 `AppRecency.swift` 与上游的 `VersionLabel.swift` 撞了同一组 ID，`AppRecency` 改用 `AF30`/`FF30`。
- 上游新增文案的本地化：被上游搬了位置的两处（`RemoteCopy` → `RemoteDialPolicy.swift`，桌面按钮 → `DesktopDisplays.swift`）在合并提交里补回包装；其余新增文案（一键更新、全屏、画中画、只读视图、版本标签等）在后一个提交里改成 `String(localized:comment:)` 并补齐简体中文，日志保持英文；几个检查的 `mutants.py` 匹配模式随文案行更新。术语表加了全屏、画中画、立即更新、每夜构建版等。
- 验证（Xcode 26.6 / Swift 6.3.3）：`swift build -c release` 通过；iOS 模拟器 Debug 构建通过；`Tests/checks/run-all.sh` 全部通过；`Scripts/l10n-check.py` 两个目录零缺译、格式符一致；`Scripts/fork-check.py --against a32de106^1` 标记全部通过、译文全部还在，"可能丢失的行"逐条看过。
- 没有验证：真机与模拟器上的实际显示（全屏与顶栏折叠叠加的手感、中文排版是否截断）、Sill.app 的一键更新、任何 mutants（`desktop-displays`、`remote-rules`、`update-install`、`full-screen`、`picture-in-picture` 的匹配模式改过，只核对了模式能在源码里匹配到，`version-label` 的 26 个跑过）。
- 留给用户决定：上游的全屏与 fork 的顶栏折叠功能重叠，是否只留一个；全屏时是否隐藏语音悬浮球；"escape gesture"、"Start PiP Automatically" 等几条译法。
