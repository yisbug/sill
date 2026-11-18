# 本 fork 相对上游的改动清单

本仓库是 [Saffsanity/sill](https://github.com/Saffsanity/sill)（远端 `upstream`）的 fork（远端 `origin`，yisbug/sill）。
这份清单记录 **只在本 fork 里有、上游没有** 的改动，用途只有一个：每次把上游合进来之后，确认这些改动没有被覆盖；被覆盖的补回来。

- 上次同步点：`f224323`（上游 PR #220 的合并提交）。每次同步完成后把这一行改成新的同步点。
- 每一项下面的 `fork-check` 代码块是给 `Scripts/fork-check.py` 读的标记，不是示例，改动时保持格式。

## 合并上游的步骤

1. 记下合并前的位置，后面检查要用：`git fetch upstream && git rev-parse HEAD`（下文记作 `<合并前>`）。
2. 合并：`git merge upstream/main`。不 rebase，不改写已推送的历史。冲突两边的功能都保留；拿不准保留哪边就停下来问。
3. 冲突解决完、提交合并 **之前** 先跑检查：

   ```bash
   Scripts/fork-check.py --against <合并前>
   ```

   合并还没提交时 `<合并前>` 就是 `HEAD`；已经提交了就用 `ORIG_HEAD` 或记下的哈希。
4. 按输出处理（见下一节），改完再跑，直到标记和译文两部分通过、"可能丢失的行"逐条看过。
5. 上游新增的用户可见文案补上译文：`Scripts/l10n-sync.sh`，再 `Scripts/l10n-check.py`（要零缺失）。
6. 验收：`swift build -c release`；`Tests/checks/run-all.sh`；iOS 用 Xcode 26 构建
   （`xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Debug -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGN_IDENTITY=- build`）；
   Debug 通过不代表 Release 通过（`#if DEBUG` 里的代码不同），Release 配置另跑一次
   `xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
7. 更新本文件：同步点；上游已经自己做了的项删掉；合并时不得不改写的项改标记。

## 检查脚本说什么、怎么补

`Scripts/fork-check.py` 做三件事，退出码 0 表示都干净，1 表示标记或译文有问题，2 表示只剩"可能丢失的行"要人看。

| 部分 | 查什么 | 出问题时怎么补 |
|---|---|---|
| 标记 | 本文件每一项的 `fork-check` 块：文件还在、关键内容还在、不该回来的内容没有回来 | 看该项的"提交"，`git show <提交> -- <文件>` 找到原改动，按现在的代码重新做一遍 |
| 译文 | `--against` 那个版本里有简体中文译文的条目，现在是否还有、是否被改 | `git show <合并前>:<目录文件>` 取回原译文；条目整个消失通常是上游删了这句文案，确认后忽略 |
| 可能丢失的行 | fork 自己加的每一行（同步点到 `<合并前>` 的净增行），现在的文件里还有没有 | `git diff $(git merge-base <合并前> upstream/main) <合并前> -- <文件>` 看 fork 原来怎么改的，对照现在的文件判断：上游重写了同一处（把 fork 的意图搬到新代码上）还是合并时选错了边（直接补回） |

"可能丢失的行"会有误报：上游改了同一行、或者这一行被合理地改写，都会列出来。它的作用是不漏，判断靠人。加 `--verbose` 列出每个文件的全部丢失行。

## 改动清单

### F01 用 Xcode 26 编译：去掉 iOS 27.1 的折叠屏接口

- 是什么：本机只有 Xcode 26.6（没有 iOS 27.1 SDK），所以去掉了 iPhone Duo 的 `onHingeChange`、`DeviceHingeContext`、`reservedRegions(kind:)`；真机上姿态恒为 unknown。`DuoPosture` 的纯规则和调试 stand-in 保留。另外两处为 Xcode 26 让路：`grammarCheckingType` 只在 Swift 6.4 以上编译；`StreamScreen.body` 的修饰链拆成 `screen` 与 `body` 两段，避免类型检查超时。Release 配置下 `StreamScreen` 另有一个显式的 `init(client:)`：`scannerOverride` 是带默认值的私有 `var`，合成的初始化器是私有的，Xcode 26 的编译器因此报 `'StreamScreen' initializer is inaccessible`（Debug 有自己的初始化器，不受影响）。
- 提交：`4e0f8bc`、`16b3268`（audio-playout 检查拆长闭包）、Release 初始化器见 `git log -S'init(client: StreamClient) { self.client = client }' -- iOSClient/StreamScreen.swift`。
- 合并时注意：上游的 Duo 工作还在继续，几乎每次都会重新带回这些接口，或者新增别的 iOS 27.1 接口。标记只认得已知的三个名字，**最终以 Xcode 26 能否编译为准**。上游新写的长修饰链或长闭包也可能再次超时，拆开即可。等本机升到 Xcode 27.1，这一整项可以撤销。

```fork-check
lacks iOSClient/*.swift :: .onHingeChange
lacks iOSClient/*.swift :: DeviceHingeContext)
lacks iOSClient/*.swift :: geo.reservedRegions(
has iOSClient/InputOverlay.swift :: #if compiler(>=6.4)
has iOSClient/StreamScreen.swift :: private var screen: some View
has iOSClient/StreamScreen.swift :: init(client: StreamClient) { self.client = client }
```

### F02 简体中文本地化的基础设施

- 是什么：iOS 端 `Localizable.xcstrings` 与 `InfoPlist.xcstrings`，工程登记 `zh-Hans`；Mac 端 `Packaging/Localizable.xcstrings` 由 `make-app.sh` 用 `xcstringstool` 编进 Sill.app，`Info.plist` 声明 `en`、`zh-Hans`，并始终带一个 `en.lproj`（否则英文用户被判为只支持中文）；`Scripts/l10n-sync.sh` 提取字符串，`Scripts/l10n-check.py` 查覆盖与格式符并接入 CI；术语表 `docs/l10n-glossary.md`。
- 提交：`6214a28`、`da6f9e4`、`1790d93`、`c744643`、`331c21d`。
- 合并时注意：`make-app.sh`、`Packaging/Info.plist`、`project.pbxproj`、`ci.yml` 上游都常改，冲突时两边都留。译文本身由脚本的"译文"部分逐条核对。

```fork-check
file iOSClient/Localizable.xcstrings
file iOSClient/InfoPlist.xcstrings
file Packaging/Localizable.xcstrings
file Scripts/l10n-sync.sh
file Scripts/l10n-check.py
file docs/l10n-glossary.md
has Scripts/make-app.sh :: xcstringstool
has Scripts/make-app.sh :: en.lproj
has Packaging/Info.plist :: zh-Hans
has iOSClient/Sill.xcodeproj/project.pbxproj :: zh-Hans
has .github/workflows/ci.yml :: Scripts/l10n-check.py
has Tests/checks/common.sh :: compile_check_localizations
```

### F03 用户可见文案改成可本地化写法

- 是什么：协议层、iOS 端、Mac 端的用户可见文案一律写成 `String(localized: "English", comment: "中文")`（约 60 个文件）；数量文案用字符串目录的复数变体；界面上的时长、码率、帧率、延迟按区域格式化（端口、像素尺寸、日志保持原样）；画质预设名分界面本地化版和日志英文版；几个检查的 `mutants.py` 跟着改了匹配文本。
- 提交：`ae06c84`、`f88fb02`、`b6110a7`、`331c21d`。
- 合并时注意：这是最容易被覆盖的一项——上游改任何一句文案，合并时很容易整行取上游的版本，本地化包装就没了。标记只抽查几个文件，**主要靠"可能丢失的行"**。上游新增的文案是新工作（包装、提取、翻译），不算被覆盖，走步骤 5。

```fork-check
has Sources/StreamProtocol/HostSettings.swift :: String(localized:
has Sources/StreamProtocol/ClipboardPolicy.swift :: String(localized:
has Sources/SillHost/LockPolicy.swift :: String(localized:
has Sources/SillMenuBar/StatusText.swift :: String(localized:
has Sources/SillMenuBar/SettingsPanes.swift :: String(localized:
has iOSClient/TourPolicy.swift :: String(localized:
has iOSClient/HostSettingsPanel.swift :: String(localized:
has iOSClient/GoodbyePolicy.swift :: String(localized:
```

### F04 Mac 按设备语言生成发给设备的说明

- 是什么：`Hello` 新增可选的 `languages`；Mac 发给设备的文字（拒绝提示、音频与虚拟显示器说明、语音结果、菜单与锁屏提示）按该连接的语言生成，只在 Sill 支持的语言里匹配，区分中文字形，否则英文。
- 提交：`331c21d`。
- 合并时注意：`Compatibility.swift` 的 `Hello` 上游也会加字段，两边的字段都留，都是可选的。

```fork-check
has Sources/StreamProtocol/Compatibility.swift :: public var languages: [String]?
has Sources/StreamProtocol/Compatibility.swift :: public static func locale(languages:
```

### F05 语音输入：协议

- 是什么：kind 100 `voiceClip`、101 `voiceResult`、102 `voiceCancel`，`WindowList.voice`（1 表示这台 Mac 能接语音输入），类型在 `Sources/StreamProtocol/Voice.swift`。只增不改。
- 提交：`a632a5c`、`4896c29`。
- 合并时注意：种类号选 100–102 是为了避开上游的号段（合并时上游用到 45）。**每次合并看一眼上游 `StreamMessageKind` 的最大号**，接近 100 就要和上游对齐。`compatibility`、`display-wake`、`pointer-control`、`protocol` 四个检查里登记了这三个种类，上游改这些检查时别丢。

```fork-check
file Sources/StreamProtocol/Voice.swift
has Sources/StreamProtocol/StreamMessage.swift :: case voiceClip = 100
has Sources/StreamProtocol/StreamMessage.swift :: case voiceResult = 101
has Sources/StreamProtocol/StreamMessage.swift :: case voiceCancel = 102
has Sources/StreamProtocol/Switcher.swift :: public var voice: Int?
```

### F06 语音输入：Mac 端 VoiceBridge

- 是什么：Mac 把语音片段交给本机的 meeppo-voice 识别（发现文件 `local-api.json`，默认 TypefreeDemo 目录，`voiceDataDirectory` / `--voice-dir` / `SILL_TEST_VOICE_DIR`），文字走 kind 8 文字的同一入口注入；Settings › General 有一行状态；测试替身 `Scripts/voice-standin.py`，`sillclient.py` 的 `--voice`、`--voice-cancel`。
- 提交：`c963aeb`。
- 合并时注意：`StreamCoordinator`、`StreamServer`、`HostConfig`、`InputInjector`、`TestHooks` 是上游改动最密的文件，语音的接线点（收 kind 100/102、发 101、窗口列表里的 `voice`）容易在冲突里丢。

```fork-check
file Sources/SillHost/VoiceBridge.swift
file Sources/SillHost/VoicePolicy.swift
file Scripts/voice-standin.py
has Sources/SillHost/HostConfig.swift :: voiceDataDirectory
has Sources/SillHostCLI/main.swift :: --voice-dir
has Sources/SillHost/StreamCoordinator.swift :: VoiceBridge
has Sources/SillHost/StreamServer.swift :: voiceClip
has Scripts/sillclient.py :: --voice-cancel
```

### F07 语音输入：iOS 悬浮球

- 是什么：串流画面上的悬浮球，点按录音、再点提交，拖动贴边；设置里本机组的"Voice Input"开关（`Sill.voiceInput`）；麦克风用途说明及中文译文；⌃⌥R 与 Esc；DEBUG 参数 `-SillVoice…`。
- 提交：`8ccfe3e`。
- 合并时注意：`StreamScreen.swift` 里悬浮球是 ZStack 里的兄弟视图（必须后画才收得到触摸，不能改成 `.overlay`）；`Info.plist` 与 `Info-Debug.plist` 两个都要有麦克风说明；新文件的 `project.pbxproj` 条目各 4 处。

```fork-check
file iOSClient/VoiceInputButton.swift
file iOSClient/VoiceInputPolicy.swift
file iOSClient/VoiceRecorder.swift
has iOSClient/Info.plist :: NSMicrophoneUsageDescription
has iOSClient/Info-Debug.plist :: NSMicrophoneUsageDescription
has iOSClient/Sill.xcodeproj/project.pbxproj :: VoiceInputButton.swift
has iOSClient/Sill.xcodeproj/project.pbxproj :: VoiceInputPolicy.swift
has iOSClient/Sill.xcodeproj/project.pbxproj :: VoiceRecorder.swift
has iOSClient/StreamScreen.swift :: VoiceInputLayer
has iOSClient/VoiceInputPolicy.swift :: static let switchKey = "Sill.voiceInput"
has iOSClient/HostSettingsPanel.swift :: @AppStorage(VoiceInputPolicy.switchKey)
```

### F08 横屏精简顶栏与应用图标窗口条

- 是什么：顶栏 86→48 pt，按钮只留图标；窗口条改成每个应用一个图标，当前应用第一、其余按最近使用排序（`AppRecency`），多窗口有角标，点按轮换、长按列出窗口；取消手动拖动排序；设置里"顶栏显示窗口缩略图"（`Sill.barThumbnails`，默认关）可恢复上游的样式。导览目标同步改了。
- 提交：`9d4ac02`。
- 合并时注意：上游对顶栏（`TopBar`、`WindowStrip`、缩略图按住时长、Aa、Menus 按钮）的改动要同时落到两种样式上；`TourPolicy` 与 `TourOverlay` 的目标也要对上。

```fork-check
file iOSClient/AppRecency.swift
file Tests/checks/app-recency/main.swift
has iOSClient/Sill.xcodeproj/project.pbxproj :: AppRecency.swift
has iOSClient/StreamScreen.swift :: AppRecency
has iOSClient/HostSettingsPanel.swift :: Sill.barThumbnails
```

### F09 串流界面隐藏状态栏

- 是什么：串流界面在所有 iPad 和 iPhone 上隐藏状态栏，顶栏贴着屏幕顶边；连接界面等照常显示。上游只在 iPhone Duo 内屏隐藏的 `duoStatusBar` 修饰器已删除。
- 提交：`7bd0484`。
- 合并时注意：上游若改 `duoStatusBar` 的调用处，合并后不要让它回到 `StreamScreen`。

```fork-check
has iOSClient/StreamScreen.swift :: Color.clear.statusBarHidden(true)
lacks iOSClient/*.swift :: func duoStatusBar(
lacks iOSClient/StreamScreen.swift :: .duoStatusBar(
```

### F10 横屏顶栏折叠

- 是什么：顶栏最右的收起按钮；收起后顶边留一个半透明、可左右拖动的浮动入口，点它恢复；状态与位置记在本机（`Sill.barCollapsed`、`Sill.barHandle`）；导览显示时临时展开；收起时剪贴板提示改到右下角、语音悬浮球避开入口。规则在 `BarCollapse`，检查 `bar-collapse`。
- 提交：`4f80231`。
- 合并时注意：浮动入口同样是 ZStack 里后画的兄弟视图；`BarMetrics.clearing` 按 6 个按钮算（上游是 5）；`menusFit` 的宽度减去了收起按钮。

```fork-check
file iOSClient/BarCollapse.swift
file Tests/checks/bar-collapse/main.swift
has iOSClient/Sill.xcodeproj/project.pbxproj :: BarCollapse.swift
has iOSClient/StreamScreen.swift :: BarCollapseHandle
has iOSClient/StreamScreen.swift :: BarCollapse.hidesBar(
has iOSClient/StreamScreen.swift :: collapse: collapseBar
has iOSClient/Localizable.xcstrings :: "Hide the toolbar"
has iOSClient/Localizable.xcstrings :: "Show the toolbar"
```

### F11 Mac 端：窗口拒绝改大小时重试

- 是什么：把窗口挪到虚拟显示器时，有的 App（ChatGPT）拒绝"先挪位置再改大小"；大小原封未动时改用"先改大小、再挪位置、再改大小"重试（`WindowSizer.resizeFirst`），并等窗口缩到位再开始截取。日志计数 `vd.resizedAgain`、`vd.refusedAgain`。
- 提交：`be8450b`、`2b93f11`。
- 合并时注意：`VirtualStage.prepare` 的等待逻辑上游改过多次，重试要接在"第一次移动后大小没变"的分支上。

```fork-check
has Sources/SillHost/WindowSizer.swift :: func resizeFirst(
has Sources/SillHost/VirtualStage.swift :: sizer.resizeFirst(
has Sources/SillHost/VirtualStage.swift :: vd.resizedAgain
has Sources/SillHost/VirtualStage.swift :: vd.refusedAgain
```

### F12 检查与 CI

- 是什么：新增四组纯检查 `app-recency`、`voice`、`bar-collapse`、`phone-stream`（各有 `run.sh`、`main.swift`、`mutants.py`），登记在 `Tests/checks/README.md` 的表格和 `ci.yml` 的 mutants 矩阵里；`tour`、`compatibility`、`display-wake`、`pointer-control`、`protocol` 几个检查跟着功能改了。
- 提交：`9d4ac02`、`39c0d25`、`4f80231`、`a632a5c`。
- 合并时注意：`ci.yml` 的矩阵是一整行，上游每加一个检查这一行就冲突，合并后三个名字都要在；README 表格同理。

```fork-check
file Tests/checks/voice/main.swift
file Tests/checks/voice/module.txt
has .github/workflows/ci.yml :: , app-recency,
has .github/workflows/ci.yml :: , bar-collapse,
has .github/workflows/ci.yml :: , voice,
has .github/workflows/ci.yml :: , phone-stream,
has Tests/checks/README.md :: | `app-recency` |
has Tests/checks/README.md :: | `bar-collapse` |
has Tests/checks/README.md :: | `phone-stream` |
has Tests/checks/README.md :: | `voice` |
```

### F14 iPhone 串流界面：强制横屏、图标 Dock 栏、可调的默认缩放

- 是什么：iPhone 的串流界面只允许横屏（`SillAppDelegate.supportedInterfaceOrientationsFor`，串流界面出现时置位并请求转横屏，消失时只解锁、不转回；连接界面照旧自由旋转），不再画竖屏的「画面 + 缩略图 + 按键 + 触摸板」排布，改画和 iPad 横屏一样的图标 Dock 栏（`Sill.barThumbnails` 开关 iPhone 也有）；旋转没完成、屏幕还是竖的时不发视口。文字大小（Aa）存在 `Sill.textScale`，顶栏的 Aa 和设置面板新增的「Text Size」读写同一个值，iPhone 没存过是 0.75×，iPad 是 Off；导览里 iPhone 不再提示「竖起手机用按键和触摸板」。规则在 `PhoneStream`，检查 `phone-stream`。
- 提交：`git log --oneline --diff-filter=A -- iOSClient/PhoneStream.swift`（新增该文件的那次提交）。
- 合并时注意：`StreamScreen.screen` 里的布局分支（`drawnLayout`）、`landscape(bar:)`、`appMenuWindows`、`tourThumbnails` 三处原来的 `DuoLayout.phoneArrangement` 特殊处理已去掉，上游若改回来要保留去掉的结果；`PhonePortraitLayout`、`PortraitStreamScreen` 的手机排布代码保留不删，只是 iPhone 走不到；`textScale` 不再是 `@State`，上游若改 `textScale` 的声明或调用处，要继续经 `textScaleBinding`。

```fork-check
file iOSClient/PhoneStream.swift
file Tests/checks/phone-stream/main.swift
has iOSClient/Sill.xcodeproj/project.pbxproj :: PhoneStream.swift
has iOSClient/SillAppDelegate.swift :: supportedInterfaceOrientationsFor
has iOSClient/StreamScreen.swift :: PhoneStream.
has iOSClient/HostSettingsPanel.swift :: PhoneStream.textScaleKey
has .github/workflows/ci.yml :: , phone-stream,
has Tests/checks/README.md :: | `phone-stream` |
```

### F15 串流界面：画面铺满、浮动入口更醒目、语音球长按菜单、启动续连

- 是什么：
  - 横屏串流画面去掉 8 pt 黑框和圆角，左右伸进安全区（刘海、灵动岛一侧），顶栏底色也铺到两侧；剪贴板芯片和语音球只放在画面落在安全区里的部分（`StreamScreen.safePanel`）。剩下的黑边只来自画面与 Mac 窗口比例不同（Aa 为 Off，或串流桌面）。
  - 顶栏收起后的浮动入口不透明度调高（底色 0.85、整体 0.92，加阴影）。
  - 语音球空闲时底色略透明（`VoiceInputPolicy.idleFillOpacity` 0.78）；长按弹出系统菜单，紧挨着球：全选并删除、全选、全选并复制、全选并剪切、粘贴、撤销、重做、回车，按键经 `KeyChord.press` 发给 Mac（规则 `VoiceInputPolicy.QuickAction`、`strokes`，检查在 `voice`）。
  - 启动续连：App 打开时为最近连过、还能自动拨的那台 Mac 起一个自动重连（和断线重连同一条路），连接界面之上铺它上次的画面和「正在连接…」与取消；连上进串流，20 s 没连上或重连结束就回连接界面并提示（规则 `ConnectionList.resumeMacID`、`resumeState`，检查在 `connection-list`；状态 `StreamClient.launchResume`，界面 `LaunchResumeView`）。上次的画面在离开前台时（`willResignActive`）也留一张，只在磁贴样式下。
- 提交：待填。
- 合并时注意：`contentArea` 里原来的 `.padding(8)`、`clipShape(streamShape)` 与描边已去掉，上游若改这段要保留铺满；`ContentView.app` 的 `onAppear` 多一行 `startLaunchResume()`，ZStack 多一层 `LaunchResumeView`。

```fork-check
has iOSClient/StreamScreen.swift :: safePanel(
has iOSClient/StreamScreen.swift :: Palette.bar.opacity(0.85)
has iOSClient/StreamScreen.swift :: Palette.bar.ignoresSafeArea(edges: [.top, .horizontal])
has iOSClient/VoiceInputPolicy.swift :: enum QuickAction
has iOSClient/VoiceInputButton.swift :: .contextMenu {
has iOSClient/ContentView.swift :: LaunchResumeView
has iOSClient/ContentView.swift :: client.startLaunchResume()
has iOSClient/StreamClient+Remote.swift :: func startLaunchResume()
has iOSClient/StreamClient.swift :: keepPictureForLaunch()
has iOSClient/ConnectionList.swift :: static func resumeMacID
```

### F13 文档

- 是什么：`docs/voice-and-immersive-plan.md`（国际化、语音输入、精简顶栏、顶栏折叠的方案）、`docs/l10n-glossary.md`（术语表）、本文件，以及 `Scripts/fork-check.py` 和 `.claude/rules/fork-sync.md`（让每个会话在合并上游时自动想起这套流程）。
- 合并时注意：上游的 `CLAUDE.md`、`README.md`、`docs/DEVELOPMENT.md` 本 fork **没有改**，冲突时直接取上游的；fork 的说明只写在上面这几个自己的文件里，以后也这样，免得每次合并都冲突。

```fork-check
file docs/voice-and-immersive-plan.md
file docs/fork-changes.md
file Scripts/fork-check.py
file .claude/rules/fork-sync.md
```

## 维护

- 新增只在本 fork 有的改动时，在 **同一个提交** 里给本文件加一项（或并入已有项）并写上标记；标记选合并后最容易丢、又最不容易误报的那几行。
- 标记用固定字符串匹配，不是正则。三种写法：`file 路径`（文件存在）、`has 路径 :: 文本`（文件里有这段文本）、`lacks 路径 :: 文本`（没有）。路径可以用通配符：`has` 要求匹配到的文件里至少一个有，`lacks` 要求全部没有。
- 某一项被上游吸收（上游自己做了同样的事）后，整项删掉，在提交说明里写明。
