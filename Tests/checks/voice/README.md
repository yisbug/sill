# `voice`

**Checks:** 语音输入（docs/voice-and-immersive-plan.md 第 2 节）：kind 100–102 的编号与载荷（片段的大端片段号、格式、4 MiB 上限，结果与取消的 JSON，`WindowList.voice` nil 时不写）；Mac 端发现 meeppo-voice 的 `local-api.json`（数据目录的测试钩子、配置、默认与 ~ 展开，版本、端口、令牌、pid 的每种坏法与是否活着），片段（上限两侧、格式、空音频、主机读的上限），`/api/process` 的回答（polishedText 优先、空则 recognizedText、非 200 用 error 字段）与 URLError 的映射，落点与预览（200 个字符，按字符截），日志行不含文字；设备端的状态机（每个状态遇到每个事件，5,000 段随机序列的不变式）、显示与开关、贴边与按方向记忆、避让（20,000 个随机区域的不变式）、时长与音量的文字

**Compiles:** `Sources/SillHost/VoicePolicy.swift` and `iOSClient/VoiceInputPolicy.swift` with `Sources/StreamProtocol` (`module.txt`)
