#!/bin/bash
# ViewportOwner（Sources/SillHost/ViewportOwner.swift，本 fork）单独检查：几台设备同时连着时窗口按哪一台的面板
# 定尺寸。只有一台时和上游一样；别的设备发来视口只记下；有人操作的那台成为主人；主人走了换成最近用过的。
# 再用两台设备各自在每次换源后重发视口的模型跑随机会话：窗口尺寸只在有人换了设备操作时才变。
#   Tests/checks/viewport-owner/run.sh             编译并运行检查
#   Tests/checks/viewport-owner/run.sh --mutants   ViewportOwner.swift 的单点变异，每个都必须让检查失败
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/ViewportOwner.swift "$here/main.swift" -o "$out/check"
"$out/check"
