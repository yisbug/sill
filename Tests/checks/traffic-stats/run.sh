#!/bin/bash
# 流量统计的纯规则（本 fork）：按小时、按天、累计记账，过期桶的清理，近 N 小时 / N 天的补零序列，存取。
# 加 --mutants 时运行单点变异，每个变异都必须被检查抓住。
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/TrafficStats.swift "$here/main.swift" -o "$out/check"
"$out/check"
