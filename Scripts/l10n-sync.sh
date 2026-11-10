#!/bin/bash
# 把源码里的可本地化字符串同步进两个字符串目录（String Catalog）：
#   iOSClient/Localizable.xcstrings   iOS 端（iOSClient 与 StreamProtocol 的字符串）
#   Packaging/Localizable.xcstrings   Mac 端（SillMenuBar、SillHostCore 与 StreamProtocol 的字符串）
# 提取用编译器自己的 -emit-localized-strings（插值能得到正确的 %@、%lld），不用 xcstringstool 的
# 轻量解析（它对插值只给 %arg）。只同步键，翻译在目录里手工维护；已删除的键标为 stale。
#   Scripts/l10n-sync.sh          两端都同步
#   Scripts/l10n-sync.sh ios|mac  只同步一端
# 之后跑 Scripts/l10n-check.py 看哪些键还没有简体中文。
set -euo pipefail
cd "$(dirname "$0")/.."
work="$PWD/.build/l10n"
side="${1:-all}"

sync_ios() {
    local dd="$work/ios-dd"
    echo "iOS：编译以提取字符串（模拟器 Debug，不签名）…"
    xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Debug \
        -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO \
        -derivedDataPath "$dd" build >"$work/ios-build.log" 2>&1 \
        || { grep -E 'error:' "$work/ios-build.log" | head -20; echo "iOS 编译失败，日志：$work/ios-build.log" >&2; exit 1; }
    local inter="$dd/Build/Intermediates.noindex/Sill.build/Debug-iphonesimulator"
    # App 目标与 StreamProtocol 包目标各自的 stringsdata；AppIntents 的元数据不要。
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$inter" -name '*.stringsdata' ! -name 'ExtractedAppShortcutsMetadata.stringsdata' -path '*/arm64/*')
    [ "${#files[@]}" -gt 0 ] || { echo "没找到 iOS 的 stringsdata" >&2; exit 1; }
    xcrun xcstringstool sync iOSClient/Localizable.xcstrings --stringsdata "${files[@]}"
    echo "iOS：${#files[@]} 个源文件已同步进 iOSClient/Localizable.xcstrings"
}

sync_mac() {
    local sd="$work/mac-stringsdata"
    rm -rf "$sd"; mkdir -p "$sd"
    echo "Mac：编译以提取字符串…"
    swift build -c release --scratch-path "$work/mac-build" \
        -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$sd" \
        >"$work/mac-build.log" 2>&1 \
        || { grep -E 'error:' "$work/mac-build.log" | head -20; echo "Mac 编译失败，日志：$work/mac-build.log" >&2; exit 1; }
    # 协议与菜单栏都有 HostSettings.swift，公共输出目录按文件名写入，会互相覆盖。
    # 单独提取协议模块；外层目录只取主机与菜单栏，避免同一源码重复同步。
    local protocol="$sd/protocol"
    mkdir -p "$protocol"
    xcrun swiftc -swift-version 5 -parse-as-library -module-name StreamProtocol \
        -emit-module -emit-module-path "$protocol/StreamProtocol.swiftmodule" \
        -emit-localized-strings -emit-localized-strings-path "$protocol" \
        "$PWD"/Sources/StreamProtocol/*.swift >"$work/protocol-build.log" 2>&1 \
        || { grep -E 'error:' "$work/protocol-build.log" | head -20; echo "协议字符串提取失败，日志：$work/protocol-build.log" >&2; exit 1; }
    # 探针程序（CaptureProbe、VirtualDisplayProbe）不进 Sill.app，它们的字符串不要。
    local files=()
    for f in "$sd"/*.stringsdata; do
        src="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("source",""))' "$f")"
        case "$src" in
            */Sources/SillMenuBar/*|*/Sources/SillHost/*) files+=("$f") ;;
        esac
    done
    for f in "$protocol"/*.stringsdata; do files+=("$f"); done
    [ -f Packaging/Localizable.xcstrings ] || echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > Packaging/Localizable.xcstrings
    xcrun xcstringstool sync Packaging/Localizable.xcstrings --stringsdata "${files[@]}"
    echo "Mac：${#files[@]} 个源文件已同步进 Packaging/Localizable.xcstrings"
}

mkdir -p "$work"
case "$side" in
    all) sync_ios; sync_mac ;;
    ios) sync_ios ;;
    mac) sync_mac ;;
    *) echo "用法：$0 [ios|mac]" >&2; exit 2 ;;
esac
