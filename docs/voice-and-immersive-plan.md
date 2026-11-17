# 语音输入悬浮球与沉浸式全屏方案

> 状态：待评审 · 2026-11-10（台北时间）· 分支 `zh-hans`
> 范围：国际化（第 6 节，简体中文为首个语言，进行中）、语音输入、精简顶栏。互联网组网暂不处理。iPhone Duo 不再兼容。

## 1. 结论

- **语音输入**：iPad 上的悬浮球负责录音，音频经现有 Sill 会话送到 Mac，由 Mac 本机的 meeppo-voice（typefreedemo）识别，Sill 主机把识别文字当作输入打进当前串流的应用。识别服务的 Key、纠错词库和用量统计都只留在 Mac 上。
- **精简顶栏**（替代原先的沉浸式全屏）：保留现有显示模式，只把横屏顶栏从 86 pt 压到约 48 pt，按钮去掉文字只留图标，窗口缩略图换成应用图标，画面因此多出约 38 pt 高度。
- **快捷切换应用**：靠精简顶栏里的应用图标一键切换，不另加手势。

## 2. 语音输入

### 2.1 数据流

```
iPad 悬浮球（点按开始，再点提交）
  → AVAudioEngine 录音，单声道 16 kHz，AAC 压缩（约 32 kbps）
  → kind 100 voiceClip（设备 → Mac，新增，只增不改）
  → Sill 主机（SillHostCore 新模块 VoiceBridge）
  → POST http://127.0.0.1:<port>/api/process（meeppo-voice 本机接口，带令牌）
  → { recognizedText, polishedText }
  → 取 polishedText（为空时取 recognizedText）
  → 主机用现有的 InputInjector 文字输入打进当前串流应用（与设备打字同一路径：先激活应用，锁屏时被 LockGate 拦下）
  → kind 101 voiceResult（Mac → 设备：成功、失败原因、文字预览）
```

为什么在 Mac 端识别：
- Key 和纠错词库只有一份，在 Mac 上，iPad 不存凭据。
- 回填直接复用 Sill 已经很成熟的文字注入（含输入法组合、锁屏闸门、焦点激活），远程会话也能用。
- meeppo-voice 的 `/api/process` 本身只返回文字，不自己回填，不会和 Sill 重复输入。

### 2.2 需要 meeppo-voice 配合的改动（typefreedemo 仓库）

现状：后端监听 `127.0.0.1`，端口默认 8765 或随机；`/api/process` 要求请求头 `X-Typefree-Token`，令牌每次启动随机生成，只注入给自己的 WebView。外部进程拿不到。

建议改动（小，独立提交到 typefreedemo）：
1. 启动后把 `{ "port": <端口>, "token": <令牌>, "pid": <进程号>, "version": 1 }` 写到数据目录下的 `local-api.json`，权限 0600，退出时删除。数据目录按现有约定（默认 `~/Library/Application Support/TypefreeDemo`，`TYPEFREE_DATA_DIR` 可改）。
2. 文档里把 `/api/process` 的请求与响应字段列为对外稳定接口（只增不改）。

Sill 侧读取 `local-api.json`，校验 pid 还活着、端口在 127.0.0.1，再发请求；路径与数据目录走 Sill 的配置（UserDefaults `voiceDataDirectory`，默认值即上面的目录），不写死在逻辑里。

### 2.3 协议（只增不改）

种类号用 100–102：上游已占用或预留到 44，并已把 45 预留给 Pencil（#81），本 fork 避开这一段，以免日后合并上游时撞号。

| 种类 | 方向 | 载荷 |
|---|---|---|
| `WindowList.voice` | Mac → 设备 | 可选 Int：1 表示这台 Mac 能接语音（已找到 meeppo-voice 且接口可用）；nil 或缺失时设备不显示悬浮球 |
| kind 100 `voiceClip` | 设备 → Mac | 二进制：4 字节大端片段号 + 1 字节格式（1 = m4a 容器里的 AAC，AVAudioRecorder 原样写出；其余保留）+ 音频；单条上限 4 MiB（32 kbps 约 17 分钟），超出的 Mac 回 `tooLarge`；设备一次最多录 10 分钟，到时自动提交 |
| kind 101 `voiceResult` | Mac → 设备 | JSON：`clip`、`ok`、`text`（预览，最多 200 字）、`reason`（`noService` / `timeout` / `serviceError` / `locked` / `nothingStreams` / `tooLarge` / `busy`；同一设备同时只处理一个片段，第二个回 `busy`；设备遇到不认识的原因时显示 `message`）、`message`（人读的说明，按 Mac 语言） |
| kind 102 `voiceCancel` | 设备 → Mac | JSON：`clip`；Mac 中断对应请求（meeppo-voice 支持连接关闭即取消） |

### 2.4 iPad 端

- **悬浮球**：
  - 直径 56 pt，可拖动，松手后贴最近的左右边缘，位置按设备方向分别记忆。
  - 状态与 typefreedemo 的 `FloatingState` 对齐：空闲、录音中（显示波形与时长）、处理中、完成（短暂对勾）、失败（短暂提示原因）。
  - 不遮挡：自动避开顶栏、竖屏键盘行、触控板中心区域、剪贴板提示、导览卡片；沉浸模式下保持可见但半透明。
  - VoiceOver：一个按钮元素，"语音输入，点按两下开始"；录音中可用 Magic Tap 提交。
  - 硬件键盘：Ctrl+Option+R（与 typefreedemo 一致）开始或提交，Esc 取消。
- **录音**：
  - 录音时把 AVAudioSession 从 `.playback` 切到 `.playAndRecord`，并暂停播放 Mac 的声音，避免录进去；结束后恢复。
  - 首次使用时申请麦克风权限，Info.plist 加 `NSMicrophoneUsageDescription`（中英文）。
- **设置**：Settings › 本机里加"语音输入"开关（`Sill.voiceInput`，默认开；关掉即不显示悬浮球，本期不另设"显示悬浮球"开关）。
- 现有的 iPadOS 系统听写（#138）照常可用，与悬浮球互不影响。

### 2.5 Mac 端

- 新模块 `VoiceBridge`（`@MainActor` 只负责调度，网络请求在自己的队列上）：发现服务、转发音频、超时 90 秒、取消、结果回传。
- 菜单栏和 Settings › General 加一行状态："语音输入：已连接 meeppo-voice / 未找到 meeppo-voice（打开它即可）"。
- 日志：每次一行，记录片段号、音频长度、耗时、结果长度，不记录文字内容。

### 2.6 合规与隐私

- iOS 隐私清单与 App Store 隐私标签：音频由 iPad 发给用户自己的 Mac，再由 Mac 上的 meeppo-voice 发给用户自己配置的识别服务；Sill 本身不收集。需要更新 `site/privacy.html` 与 App Store 的说明文字。
- 设备离线、Mac 锁屏或未找到 meeppo-voice 时，悬浮球给出明确提示，不静默失败。

### 2.7 备选（本期不做）

- iPad 直连识别服务：Mac 未装 meeppo-voice 时也能用，但 Key 要存在 iPad 钥匙串，词库要维护两份。
- iOS 自带的离线识别（SpeechAnalyzer）作兜底：免费、离线，中文准确率低于 meeppo-voice 配置的服务。

## 3. 精简顶栏（横屏）

依据评审意见：不做沉浸式全屏，保留现有显示模式（顶栏在上、画面在下），只把顶栏变矮、变简洁。

### 3.1 现状

横屏顶栏高 86 pt（窄窗口 78 pt）。从左到右依次是：
- Apps 按钮；
- 窗口缩略图条（每个窗口一张 104×66 pt 的实时截图）；
- Menus、Aa、键盘、桌面、设置按钮，每个按钮图标下方带一行 11 pt 文字。

### 3.2 改法

| 项 | 现在 | 改后 |
|---|---|---|
| 顶栏高度 | 86 pt（窄窗口 78） | 48 pt（窄窗口 44） |
| 功能按钮 | 图标加文字标签 | 只留图标（SF Symbol，22 pt），点击区仍不小于 44×44 pt |
| 窗口条 | 每个窗口一张实时缩略图，顺序为手动拖动的排列 | 每个应用一个图标（32 pt），按最近使用排序（见下条）；当前串流的那个加高亮底；同一应用开了多个窗口时，图标右下角显示数字角标，点按依次切换该应用的窗口，长按列出窗口标题挑选 |
| Aa | 文字 "Aa" | 保持 "Aa"（它本身就是图标式文字），展开的标尺照旧 |

细节：
- **画面变大**：顶栏变矮后，画面区域多出约 38 pt 高度。新视口照常发给 Mac：开启虚拟显示时窗口会随之调整一次，属于正常行为。
- **无障碍**：去掉文字后，按钮的 VoiceOver 读音不变（原本就有完整的 accessibilityLabel）。
- **大字号**：开启辅助功能大字号时，长按按钮弹出大图标和名称（Large Content Viewer）。
- **按最近使用排序**（参考 macOS 的 ⌘Tab 切换器）：
  - 当前串流的应用排第一位并高亮，上一个用过的排第二，其余按最后使用时间往后排；从没用过的应用排在最后，按 Mac 报告的顺序。
  - "使用"包括两种：在 iPad 上点图标或从 Apps 抽屉选中；Mac 端串流的源变了（例如在 Mac 上切到别的窗口后由设备重新选中）也算。
  - 顺序记在设备上，按 Mac 分别保存，重启后保留。
  - 为了避免图标在手指下跳动：点图标后先原地高亮，约 1 秒后（且手指已离开顶栏）再带动画重排；用 Apps 抽屉切换时同理。
  - 这样"点第二个图标"总是回到上一个应用，相当于 ⌘Tab 一次。
- **快捷切换**：点应用图标即切换到该应用最近使用的那个窗口，复用现有的选源请求（kind 6），不改协议。长按出现的红黄绿三个按钮（关闭、最小化、全屏）保持现有行为，改为挂在应用图标上（作用于该应用当前窗口）。
- **手动拖动排序**：在应用图标模式下取消，因为与"最近使用排序"冲突；缩略图模式（见下）保留原来的拖动排序。
- **缩略图开关**：Settings 里加"顶栏显示窗口缩略图"开关，默认关（显示应用图标）；打开后恢复现在的缩略图样式和高度，给需要分辨同一应用多个窗口的人用。
- **适用范围**：
  - 竖屏的窗口栏和手机竖屏布局本期不改。
  - iPad 竖屏上半部分的窗口栏如果也希望变成应用图标，请在评审里说明。

### 3.3 不做的部分

- 沉浸式全屏、顶栏自动隐藏、边缘手势：按评审意见取消。
- 按 iPad 尺寸新建虚拟显示器的扩展屏模式：后续再议。

## 4. 待你决定的问题（括号内为默认值）

1. 语音识别放在 Mac 端（是）。如果希望没有 Mac 端 meeppo-voice 时也能用，请说明，那就需要同时做 2.7 的 iPad 直连。
2. ~~是否允许修改 typefreedemo 仓库~~ 已定：允许，改动完成验证后直接合并到其主分支并推送。
3. 识别结果是否先在 iPad 上预览、确认后再打进 Mac（否，直接打进去，悬浮球旁短暂显示预览，可撤销则用 Mac 的 ⌘Z）。
4. 精简顶栏的高度（48 pt；窄窗口 44 pt）。
5. 同一应用多个窗口时的处理（一个图标加数字角标，点按依次切换，长按挑选）。
6. 图标排序按最近使用，并取消手动拖动排序（是；当前应用排第一，切换后约 1 秒再重排）。
7. 是否保留"显示窗口缩略图"开关（保留，默认关）。

## 5. 实施顺序与验收

1. 简体中文本地化（进行中）：两端全部界面与 VoiceOver 文字有中文，`Scripts/l10n-check.py` 零缺失；`Tests/checks/run-all.sh` 全部通过；模拟器中文截图核对主要界面。
2. 语音输入：
   - 协议的纯逻辑检查（新增 `Tests/checks/voice`）。
   - 本机端到端：用一个替身 HTTP 服务模拟 `/api/process`，跑合成测试主机与模拟器，验证文字打进合成主机的输入日志。
   - 真机（需要你）：iPad 录一句中文，Mac 的 TextEdit 里出现识别结果。
3. 精简顶栏：
   - 布局与导览检查（`tour` 里横屏顶栏的目标位置会变，需要同步更新）。
   - 截图回归：横屏几种 iPad 尺寸，默认字号和最大字号，中英文各一组。
   - 模拟器里验证点应用图标切换窗口、多窗口角标、长按挑选，以及缩略图开关切回旧样式。
   - 真机手感需要你试。

## 6. 国际化（i18n）方案

依据评审意见：中文不是单独做一次翻译，而是一套能持续加语言的国际化方案。简体中文是第一种目标语言，以后加日文、繁体中文等只需加译文，不用再改代码。

### 6.1 已有的基础（本分支已提交）

- 两端各一个字符串目录（String Catalog，`.xcstrings`）：iOS 用 `iOSClient/Localizable.xcstrings` 与 `InfoPlist.xcstrings`，Mac 用 `Packaging/Localizable.xcstrings`（由 `make-app.sh` 编译进 Sill.app）。目录本身支持任意多种语言、复数变体和设备变体。
- `Scripts/l10n-sync.sh` 用编译器提取全部可本地化字符串并同步进目录；`Scripts/l10n-check.py` 检查每种语言的覆盖率和格式符。
- 开发语言是英文，作为所有语言的兜底。

### 6.2 代码约定（所有新代码都要遵守）

1. **用户可见文字一律可本地化**：
   - SwiftUI 字面量本身就可以本地化；
   - `String` 类型的文案用 `String(localized:comment:)`，整句包装，插值写在句子里，不拼接碎片；
   - comment 写清显示位置和插值含义，供译者参考。
2. **复数与数量**：
   - 用目录的复数变体（plural variations），不在代码里按英文写 `n == 1 ? … : …`；
   - 俄文、阿拉伯文等有多种复数形式，代码分支没法覆盖。
   - 现有的英文分支写法在本轮统一改成单个键加复数变体，英文的 one/other 写进目录。
3. **数字、时长、码率、日期按系统区域格式化**：
   - 用 `FormatStyle`，例如 `.number`、`Duration.formatted()`、`Measurement`；
   - 不手写 `"\(x) s"`、`"\(n) Mbps"` 这类单位拼接。
   - 例外：日志不受此限。
4. **排版不假设语言**：
   - 不按空格断词（例如 `ThumbnailHold.titleLines` 现在按英文单词分行，要改成按系统的换行规则）；
   - 不写死依赖英文宽度的尺寸；
   - 用 leading/trailing 而不是 left/right，为以后的阿拉伯文、希伯来文等从右到左语言留路（本期不做从右到左的适配和验证）。
5. **日志、协议字段、存储键不本地化**（保持英文，供排障和测试）。

### 6.3 跨设备文案按设备语言

- Mac 发给设备显示的句子（`Goodbye.message`、`PairResult.message`、`audioNote`、`virtualDisplayNote`、语音结果的 `message` 等）目前用 Mac 的语言生成。iPad 与 Mac 语言不同时会显示错语言。
- 改法：`Hello` 加可选字段 `languages`（设备的首选语言列表，只增不改）；Mac 按每个连接选语言生成这些句子，用 `String(localized:locale:)` 指定语言，找不到就回落英文。
- 老版本设备不发这个字段，Mac 就用自己的语言，与现状一致。

### 6.4 检查与测试

- **检查程序加载英文目录**：
  - `Tests/checks` 的各检查用 swiftc 单独编译，运行时没有字符串目录；改成复数变体后，回落文字会变成 "1 tries left" 这种错误英文。
  - 所以各检查在运行前把英文目录编译进可执行文件旁边的 `en.lproj`，命令行程序的 `Bundle.main` 就是可执行文件所在目录，`String(localized:)` 能找到复数规则。
  - 断言英文原句的检查因此不用改。
- **覆盖检查**：`Scripts/l10n-check.py` 改为逐语言统计，CI 里对已上线的语言要求零缺失、格式符一致。
- **伪语言截图**：用 Xcode 的伪语言（加长文字、加重音字符）各拍一组截图，找出截断和写死宽度的地方。
- **中文截图回归**：主要界面在中文下拍一组，和英文对照。

### 6.5 翻译流程

- **日常**：直接编辑 `.xcstrings`（Xcode 打开有表格界面）。
- **外包或给译者**：iOS 用 `xcodebuild -exportLocalizations` / `-importLocalizations` 导出导入 XLIFF；Mac 目录由脚本同样导出。
- **术语表**：`docs/l10n-glossary.md` 记录专有名词与固定译法，例如：
  - "Remote Access" → 远程访问
  - "Virtual Display" → 虚拟显示器
  - "Direct Wireless Connection" → 无线直连
  - "Sill"、"Mac"、"iPad" 不译
- **新增一种语言的步骤**：
  1. iOS 工程的 `knownRegions` 和 Mac 的 `CFBundleLocalizations` 各加一项；
  2. 往两个目录里加译文；
  3. 跑覆盖检查和截图。

### 6.6 不在本期

- 网站（`site/`）和 App Store 元数据的多语言：结构上按语言分目录，本期只做简体中文的 App Store 文字，网站后续再做。
- 从右到左语言的实际适配与验证。
- 应用内切换语言：依赖系统的"按应用设置语言"（iOS 设置 › Sill › 语言；macOS 系统设置 › 通用 › 语言与地区 › 应用程序）。

## 定稿后执行

- [ ] typefreedemo：启动时写出 `local-api.json`（port、token、pid、version，权限 0600，退出删除），补测试与文档，验证通过后合并主分支并推送。
- [ ] i18n：复数分支统一改成目录复数变体，检查程序运行前编译英文目录进 `en.lproj`
- [ ] i18n：数字、时长、码率改用 FormatStyle；`ThumbnailHold.titleLines` 改为不按空格断词
- [ ] i18n：`Hello.languages` 与 Mac 按连接语言生成发给设备的句子（6.3）
- [ ] i18n：`l10n-check.py` 逐语言统计，CI 接入；写 `docs/l10n-glossary.md`；伪语言与中文截图回归


## 顶栏折叠

- 仅横屏支持：顶栏右侧点击收起，串流画面扩展至原顶栏区域；顶边半透明入口可点击展开、左右拖动并避开书本姿态的折痕。
- 折叠开关存于 `Sill.barCollapsed`（默认关闭），入口横向比例存于 `Sill.barHandle`（默认 1，最右侧），均只在设备本地持久化。
- 显示条件、位置夹取、折痕避让与占位矩形由纯规则 `BarCollapse` 决定；剪贴板提示和语音悬浮球避让入口。
- 导览显示时临时展开顶栏，不改变保存的折叠开关；竖屏布局保持原样，不改变 Mac 协议。
