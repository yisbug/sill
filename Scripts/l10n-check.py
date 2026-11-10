#!/usr/bin/env python3
"""检查字符串目录的简体中文覆盖与格式符一致性。

  Scripts/l10n-check.py                 两个目录都查，有缺失或格式符不一致时退出码为 1
  Scripts/l10n-check.py --list-missing  逐条列出缺译的键
  Scripts/l10n-check.py --apply FILE    把 FILE（JSON：{"英文键": "中文", ...}）写进两个目录里已有的同名键

不检查已标 stale 的键（源码里已不存在）和标了 shouldTranslate: false 的键。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [ROOT / "iOSClient/Localizable.xcstrings", ROOT / "Packaging/Localizable.xcstrings"]
LANG = "zh-Hans"
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|u|llu|%)")


def specs(text):
    """格式符的多重集合（位置参数 %1$@ 视同 %@），%% 不算。"""
    out = []
    for m in SPEC.finditer(text):
        s = re.sub(r"\d+\$", "", m.group(0))
        if s != "%%":
            out.append(s)
    return sorted(out)


def zh_values(entry):
    """一个键的全部中文取值：stringUnit 一个，或复数/设备变体的每一项。"""
    loc = entry.get("localizations", {}).get(LANG)
    if not loc:
        return []
    vals = []

    def walk(node):
        if isinstance(node, dict):
            unit = node.get("stringUnit")
            if unit and unit.get("value") is not None and unit.get("state") in ("translated", "needs_review"):
                vals.append(unit["value"])
            for k, v in node.items():
                if k != "stringUnit":
                    walk(v)

    walk(loc)
    return vals


def check(path, list_missing):
    if not path.exists():
        print(f"{path.relative_to(ROOT)}：不存在")
        return 1
    data = json.loads(path.read_text())
    missing, mismatch, total = [], [], 0
    for key, entry in data["strings"].items():
        if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
            continue
        if not key.strip() or not re.search(r"[A-Za-z]", key):
            continue  # 纯符号、数字、空白：无需翻译
        total += 1
        vals = zh_values(entry)
        if not vals:
            missing.append(key)
            continue
        want = specs(key)
        for v in vals:
            # 复数变体里允许省略数字本身（例如 "一次"），所以只要求不多出键里没有的格式符
            if [s for s in specs(v) if s not in want] or (len(vals) == 1 and specs(v) != want):
                mismatch.append((key, v))
    rel = path.relative_to(ROOT)
    print(f"{rel}：需翻译 {total} 条，已译 {total - len(missing)} 条，缺 {len(missing)} 条，格式符不一致 {len(mismatch)} 条")
    if list_missing:
        for k in missing:
            print("  缺：", json.dumps(k, ensure_ascii=False))
    for k, v in mismatch:
        print("  格式符不一致：", json.dumps(k, ensure_ascii=False), "→", json.dumps(v, ensure_ascii=False))
    return 1 if missing or mismatch else 0


def apply(file):
    table = json.loads(Path(file).read_text())
    for path in CATALOGS:
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        n = 0
        for key, zh in table.items():
            entry = data["strings"].get(key)
            if entry is None:
                continue
            entry.setdefault("localizations", {})[LANG] = {"stringUnit": {"state": "translated", "value": zh}}
            n += 1
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        print(f"{path.relative_to(ROOT)}：写入 {n} 条")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--apply"]:
        apply(args[1])
        sys.exit(0)
    sys.exit(max(check(p, "--list-missing" in args) for p in CATALOGS))
