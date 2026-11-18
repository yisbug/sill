# 本地化术语表

界面文字翻译时统一使用以下译法。新增语言时在表里加一列。规则见 `docs/voice-and-immersive-plan.md` 第 6 节。

## 不翻译的专有名词

Sill、Mac、iPad、iPhone、Apple、Apple Pencil、Magic Keyboard、Mission Control、App Exposé、Spaces（空间可写作"桌面空间"，见下表）、VoiceOver、Switch Control、Retina、Tailscale、WireGuard、Bonjour、AWDL、HEVC、AAC、TestFlight、App Store、GitHub、Finder、Terminal（终端，见下表）、Universal Control、Stage Manager、Wi‑Fi、USB、VPN、Mbps、fps、pt。

快捷键符号（⌘ ⌥ ⌃ ⇧ ⎋）、键帽文字（esc、tab、ctrl、opt、cmd、shift）保持原样。

## 固定译法

| English | 简体中文 | 说明 |
|---|---|---|
| Connect / Connected / Disconnect | 连接 / 已连接 / 断开连接 | |
| Pair / Paired / Pairing / Unpair | 配对 / 已配对 / 配对中 / 取消配对 | |
| pairing code / code | 配对码 / 代码 | 12 位数字码称"配对码" |
| Require pairing | 需要配对 | |
| Remote Access | 远程访问 | |
| away from home / at home | 外出时 / 在家时 | 画质设置里的"Away from home"作分组标题时译"外出时" |
| Direct Wireless Connection | 无线直连 | |
| Virtual Display | 虚拟显示器 | |
| Desktop | 桌面 | 指整块屏幕的串流源 |
| window / app | 窗口 / 应用 | 不用"程序""App" |
| Apps (the drawer) | 应用 | 顶栏按钮 |
| Menus | 菜单 | |
| Settings | 设置 | |
| Keyboard | 键盘 | |
| Text size / Aa | 文字大小 / Aa | Aa 保留 |
| Larger Picture | 更大画面 | |
| Quality | 画质 | |
| Resolution / Standard / Retina | 分辨率 / 标准 / Retina | |
| Frame Rate / Frame rate limit | 帧率 / 帧率上限 | |
| Prioritize Encoding Speed | 优先编码速度 | |
| Low / Efficient / Balanced / High / Pro / Ultra / Extreme | 低 / 省流 / 均衡 / 高 / 专业 / 超高 / 极致 | 画质预设名 |
| Send Audio / Mute | 发送声音 / 静音 | |
| Beta | 测试版 | 标签 |
| Clipboard / Share clipboard / Paste on ‹Mac› | 剪贴板 / 共享剪贴板 / 在 ‹Mac› 上粘贴 | |
| Three-Finger Gestures | 三指手势 | |
| Reverse Scrolling | 反向滚动 | |
| Hold to Show Window Controls | 按住显示窗口控制 | |
| Take the Tour / tour | 使用导览 / 导览 | |
| trackpad / pointer / cursor | 触控板 / 指针 / 光标 | |
| tap / touch and hold / drag / pinch / swipe | 轻点 / 按住 / 拖移 / 捏合 / 轻扫 | 沿用 iOS 官方用词 |
| click / right-click / double-click | 点按 / 右键点按 / 连按两次 | 沿用 macOS 官方用词 |
| full screen / minimize / close | 全屏 / 最小化 / 关闭 | |
| Screen Recording / Accessibility / Local Network | 屏幕录制 / 辅助功能 / 本地网络 | 系统权限名，与系统设置一致 |
| Privacy & Security | 隐私与安全性 | |
| System Settings | 系统设置 | |
| Launch at Login | 登录时打开 | |
| Show Log | 显示日志 | |
| Check for updates | 检查更新 | |
| firewall | 防火墙 | |
| Terminal | 终端 | 指 macOS 的"终端"App |
| hardware encoder / software encoder | 硬件编码器 / 软件编码器 | |
| Voice input | 语音输入 | |
| Full Screen | 全屏 | 视频/窗口的全屏模式 |
| Picture in Picture | 画中画 | |
| Show Controls | 显示控制 | |
| Shake to Show Controls | 摇动以显示控制 | |
| Update Now / Install Now / Try Again | 立即更新 / 立即安装 / 重试 | 设置里的更新按钮 |
| Automatically update Sill | 自动更新 Sill | |
| nightly build(s) | 每夜构建版 | |
| release | 正式版 | 指 GitHub 上正式发布的版本，区别于每夜构建版 |
| update key | 更新密钥 | 用来签名正式版的密钥；每夜构建版用"每夜密钥" |

## 写法约定

- 中文与英文、数字之间加一个空格（"在 Mac 上"、"60 fps"）；全角标点；省略号用"…"。
- 按钮和菜单项用动词短语，不加句号；说明文字是完整句子，带句号。
- 称呼用"你"，不用"您"。
- 插值占位符（%@、%lld、%1$@）原样保留，可调整顺序时用位置参数（%1$@、%2$@）。
- `**强调**` 标记（导览文案）保留在译文中，包住对应的中文词。
