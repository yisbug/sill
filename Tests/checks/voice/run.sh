#!/bin/bash
# 语音输入的纯规则（docs/voice-and-immersive-plan.md 第 2 节）：Mac 端 VoicePolicy（发现文件、片段、回答、结果、日志）与
# 设备端 VoiceInputPolicy（状态机、显示、贴边与避让、文字），连同 StreamProtocol 的 Voice.swift。
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/voice/run.sh             compile and run the check
#   Tests/checks/voice/run.sh --mutants   one-line mutants of VoicePolicy.swift, VoiceInputPolicy.swift and Voice.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
