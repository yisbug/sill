#!/bin/bash
# PickFlow（iOSClient/PickFlow.swift，本 fork）单独检查：设备上的选择同一时刻只有一次在路上，其余只留最新的
# 一个排队；这个人要的画面什么时候算到了；等不到时什么时候放下。逐条场景，再用一个会丢选择的 Mac 模型跑
# 随机会话（有 PickFlow 时 Mac 一次都不丢、最后串流的就是最后选的；不经 PickFlow 直接发时会丢，复现原问题）。
#   Tests/checks/pick-flow/run.sh             编译并运行检查
#   Tests/checks/pick-flow/run.sh --mutants   PickFlow.swift 的单点变异，每个都必须让检查失败
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PickFlow.swift "$here/main.swift" -o "$out/check"
"$out/check"
