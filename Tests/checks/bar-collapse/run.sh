#!/bin/bash
# 单独检查横屏顶栏的折叠、位置夹取、折痕避让与持久化键。
# 加 --mutants 时运行单点变异，每个变异都必须被检查抓住。
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/BarCollapse.swift "$here/main.swift" -o "$out/check"
"$out/check"
