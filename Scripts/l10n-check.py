#!/usr/bin/env python3
"""按两端声明的上线语言检查覆盖和格式符，不依赖 Xcode。

  Scripts/l10n-check.py                 缺译或格式符不一致时退出码为 1
  Scripts/l10n-check.py --list-missing  逐语言列出缺译的键
  Scripts/l10n-check.py --apply FILE [--lang zh-Hans]
      把 JSON（键到译文或完整本地化对象）写进两个目录已有的同名键。

忽略 stale、shouldTranslate: false，以及纯符号、数字和空白的键。
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [ROOT / "iOSClient/Localizable.xcstrings", ROOT / "Packaging/Localizable.xcstrings"]
SPEC = re.compile(
    r"(?P<argument>%arg)\b|%#@(?P<substitution>[^@]+)@|"
    r"%(?:(?P<position>\d+)\$)?(?P<format>[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?:hh|ll|[hlqLztj])?[diuoxXfFeEgGaAcCsSp@%])"
)


def languages_by_catalog():
    """各目录只检查其应用已声明支持的语言，不把源码语言当作译文。"""
    project = (ROOT / "iOSClient/Sill.xcodeproj/project.pbxproj").read_text()
    regions = re.search(r"\bknownRegions\s*=\s*\((.*?)\);", project, re.S)
    if not regions:
        raise ValueError("iOS 工程中没有 knownRegions")
    body = re.sub(r"/\*.*?\*/|//[^\n]*", "", regions.group(1), flags=re.S)
    ios = [item.strip().strip('"') for item in body.split(",") if item.strip()]
    with (ROOT / "Packaging/Info.plist").open("rb") as file:
        mac = plistlib.load(file)["CFBundleLocalizations"]
    return {path: sorted(set(langs) - {"en", "Base"}) for path, langs in zip(CATALOGS, (ios, mac))}


def units(node, path=()):
    """包含复数、设备变体与 substitutions 中的每个 stringUnit。"""
    if not isinstance(node, dict):
        return
    if "stringUnit" in node:
        yield path, node["stringUnit"]
    for name, child in node.items():
        if name != "stringUnit" and isinstance(child, dict):
            yield from units(child, path + (name,))


def translation_complete(localization):
    """已有译文分支都必须译完；所有复数树都必须有可用的 other 兜底。"""
    values = list(units(localization))
    if not values or any(unit.get("state") not in ("translated", "needs_review")
                         or not unit.get("value") for _, unit in values):
        return False

    def complete(node):
        if not isinstance(node, dict):
            return True
        plural = node.get("variations", {}).get("plural")
        if plural is not None and not list(units(plural.get("other", {}))):
            return False
        return all(complete(child) for child in node.values() if isinstance(child, dict))

    return complete(localization)


def source_value(source, path, key):
    """目标分支优先对照同名英文分支；其他语言特有的复数形式对照 other。"""
    def lookup(parts):
        node = source
        for part in parts:
            if not isinstance(node, dict) or part not in node:
                return None
            node = node[part]
        return node.get("stringUnit", {}).get("value") if isinstance(node, dict) else None

    value = lookup(path)
    if value is None:
        fallback = list(path)
        for index in range(1, len(fallback)):
            if fallback[index - 1] == "plural":
                fallback[index] = "other"
        value = lookup(fallback)
    return key if value is None else value


def specs(text, localization, branch=()):
    """按插值位置比较格式符，允许译文重排，但不允许遗漏、重复或类型变化。"""
    out = []
    implicit = 1
    for match in SPEC.finditer(text):
        if match.group("argument"):
            if "substitutions" not in branch:
                raise ValueError("%arg 不在 substitution 分支中")
            name = branch[branch.index("substitutions") + 1]
            substitution = localization.get("substitutions", {}).get(name)
            if not substitution:
                raise ValueError(f"缺少 substitution：{name}")
            out.append((1, substitution["formatSpecifier"].lstrip("%")))
            continue
        name = match.group("substitution")
        if name is not None:
            substitution = localization.get("substitutions", {}).get(name)
            if not substitution:
                raise ValueError(f"缺少 substitution：{name}")
            out.append((int(substitution["argNum"]), substitution["formatSpecifier"].lstrip("%")))
            continue
        fmt = match.group("format")
        if fmt == "%":
            continue
        position = int(match.group("position")) if match.group("position") else implicit
        out.append((position, fmt))
        implicit += 1
    return Counter(out)


def check(path, languages, list_missing):
    if not path.exists():
        print(f"{path.relative_to(ROOT)}：不存在")
        return 1
    data = json.loads(path.read_text())
    failed = False
    for lang in languages:
        missing, mismatch, total = [], [], 0
        for key, entry in data["strings"].items():
            if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
                continue
            has_arguments = any(match.group("format") != "%" for match in SPEC.finditer(key))
            if not key.strip() or (not re.search(r"[A-Za-z]", key) and not has_arguments):
                continue
            total += 1
            localizations = entry.get("localizations", {})
            localization = localizations.get(lang, {})
            values = list(units(localization))
            if not translation_complete(localization):
                missing.append(key)
            source = localizations.get(data.get("sourceLanguage", "en"), {})
            for branch, unit in values:
                value = unit.get("value")
                if value is None:
                    continue
                try:
                    want = specs(source_value(source, branch, key), source, branch)
                    actual = specs(value, localization, branch)
                    if actual != want:
                        mismatch.append((key, branch, value))
                except (KeyError, TypeError, ValueError) as error:
                    mismatch.append((key, branch, f"{value}（{error}）"))
        print(f"{path.relative_to(ROOT)} [{lang}]：需翻译 {total} 条，已译 {total - len(missing)} 条，"
              f"缺 {len(missing)} 条，格式符不一致 {len(mismatch)} 条")
        if list_missing:
            for key in missing:
                print("  缺：", json.dumps(key, ensure_ascii=False))
        for key, branch, value in mismatch:
            print("  格式符不一致：", json.dumps(key, ensure_ascii=False),
                  f"[{ '/'.join(branch) or 'stringUnit' }]", "→", json.dumps(value, ensure_ascii=False))
        failed |= bool(missing or mismatch)
    return int(failed)


def apply(file, lang):
    table = json.loads(Path(file).read_text())
    if not isinstance(table, dict) or any(not isinstance(value, (str, dict)) for value in table.values()):
        raise ValueError("译文文件必须是键到字符串或完整本地化对象的 JSON 对象")
    for path in CATALOGS:
        data = json.loads(path.read_text())
        count = 0
        for key, value in table.items():
            entry = data["strings"].get(key)
            if entry is None:
                continue
            entry.setdefault("localizations", {})[lang] = (
                {"stringUnit": {"state": "translated", "value": value}} if isinstance(value, str) else value
            )
            count += 1
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        print(f"{path.relative_to(ROOT)} [{lang}]：写入 {count} 条")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list-missing", action="store_true")
    parser.add_argument("--apply", metavar="FILE")
    parser.add_argument("--lang", default="zh-Hans", help="--apply 的目标语言，默认为 zh-Hans")
    args = parser.parse_args()
    try:
        if args.apply:
            apply(args.apply, args.lang)
            return 0
        languages = languages_by_catalog()
        results = [check(path, languages[path], args.list_missing) for path in CATALOGS]
        return max(results)
    except (OSError, ValueError, KeyError) as error:
        print(f"本地化检查失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
