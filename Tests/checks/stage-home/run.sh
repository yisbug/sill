#!/bin/bash
# StageHome（Sources/SillHost/StageHome.swift，本 fork）单独检查：虚拟显示器上的窗口送回原位之后的回读
# （在原位、又变回舞台上的大小、被人动过），回读什么时候可以提前结束，以及窗口带着舞台上的大小再次上来时
# 该记哪个原位。用 2026-11-18 日志里 Tabbit 和 Chrome 的实际数字。
#   Tests/checks/stage-home/run.sh             编译并运行检查
#   Tests/checks/stage-home/run.sh --mutants   StageHome.swift 的单点变异，每个都必须让检查失败
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/StageHome.swift "$here/main.swift" -o "$out/check"
"$out/check"
