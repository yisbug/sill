#!/bin/bash
# 单独检查 iPhone 串流界面的纯规则：强制横屏、横屏布局、视口发送时机、文字大小的存储键、默认值、读回与写入。
# 加 --mutants 时运行单点变异，每个变异都必须被检查抓住。
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PhoneStream.swift Sources/StreamProtocol/TextScale.swift Sources/StreamProtocol/Switcher.swift Sources/StreamProtocol/StreamMessage.swift "$here/main.swift" -o "$out/check"
"$out/check"
