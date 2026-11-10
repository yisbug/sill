#!/bin/bash
# 独立编译横屏应用栏的纯逻辑；变异检查中的每次单点修改都必须被用例抓到。
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -module-cache-path "$out/ModuleCache" iOSClient/AppRecency.swift "$here/main.swift" -o "$out/check"
"$out/check"
