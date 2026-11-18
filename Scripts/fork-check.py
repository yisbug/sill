#!/usr/bin/env python3
"""合并上游之后，检查本 fork 自己的改动有没有被覆盖。清单和标记在 docs/fork-changes.md。

用法：
  Scripts/fork-check.py                       只查标记（文件还在、关键内容还在、不该回来的没回来）
  Scripts/fork-check.py --against <合并前>    再查译文和"可能丢失的行"；<合并前> 是合并上游之前 fork 的提交
                                              （合并未提交时用 HEAD，已提交用 ORIG_HEAD 或哈希）
选项：
  --root DIR       要检查的工作区（默认是本脚本所在的仓库）；清单总是读本脚本所在仓库的那一份
  --upstream REF   上游分支（默认 upstream/main），用来算 fork 与上游的分叉点
  --verbose        "可能丢失的行"逐行全部列出（默认每个文件 5 行）

退出码：0 都干净；1 标记或译文有问题；2 只剩"可能丢失的行"需要人看；3 用法或环境错误。
只读：不改任何文件，不动 git。
"""
import argparse
import glob
import json
import re
import subprocess
import sys
from pathlib import Path

HOME = Path(__file__).resolve().parent.parent
DOC = HOME / "docs" / "fork-changes.md"
LANGUAGE = "zh-Hans"
# 太短的行（括号、空行、单个关键字）到处都有，丢没丢说明不了什么。
SHORTEST = 6


def fail(message):
    print(f"fork-check: {message}", file=sys.stderr)
    sys.exit(3)


def git(root, *arguments, check=True):
    done = subprocess.run(["git", "-C", str(root), *arguments], capture_output=True)
    if check and done.returncode != 0:
        fail(f"git {' '.join(arguments)} 失败：{done.stderr.decode(errors='replace').strip()}")
    return done.stdout.decode(errors="replace") if done.returncode == 0 else None


def markers():
    """清单里每一项的标记：[(项, 种类, 路径, 文本)]。没有标记的项算清单写错了。"""
    found, item, inside, items = [], None, False, []
    for number, line in enumerate(DOC.read_text().splitlines(), 1):
        heading = re.match(r"### (F\d+) ", line)
        if heading and not inside:
            item = heading.group(1)
            items.append(item)
        elif line.strip() == "```fork-check":
            inside = True
        elif line.strip() == "```" and inside:
            inside = False
        elif inside and line.strip():
            kind, _, rest = line.strip().partition(" ")
            path, separator, text = rest.partition(" :: ")
            if kind not in ("file", "has", "lacks") or not path or (kind != "file") != bool(separator and text):
                fail(f"{DOC.name} 第 {number} 行的标记看不懂：{line.strip()}")
            if item is None:
                fail(f"{DOC.name} 第 {number} 行的标记不在任何一项下面")
            found.append((item, kind, path.strip(), text))
    without = [name for name in items if name not in {entry[0] for entry in found}]
    if without:
        fail(f"{DOC.name} 里这些项没有标记：{', '.join(without)}")
    return found


def check_markers(root):
    problems = []
    for item, kind, pattern, text in markers():
        paths = sorted(Path(p) for p in glob.glob(str(root / pattern)) if Path(p).is_file())
        if kind == "file":
            if not paths:
                problems.append((item, f"文件不见了：{pattern}"))
            continue
        holders = [p for p in paths if text in p.read_text(errors="replace")]
        if kind == "has" and not holders:
            reason = "文件不见了" if not paths else "没有这段内容"
            problems.append((item, f"{pattern}：{reason}：{text}"))
        if kind == "lacks" and holders:
            names = ", ".join(str(p.relative_to(root)) for p in holders)
            problems.append((item, f"不该有的内容回来了（{names}）：{text}"))
    return problems


def translations(catalog):
    """字符串目录里有简体中文的条目：{条目: 译文的规范化 JSON}。"""
    result = {}
    for key, entry in catalog.get("strings", {}).items():
        localized = entry.get("localizations", {}).get(LANGUAGE)
        if localized is not None:
            result[key] = json.dumps(localized, ensure_ascii=False, sort_keys=True)
    return result


def check_translations(root, before):
    problems, notes = [], []
    for path in git(root, "ls-tree", "-r", "--name-only", before).splitlines():
        if not path.endswith(".xcstrings"):
            continue
        old = translations(json.loads(git(root, "show", f"{before}:{path}")))
        current = root / path
        if not current.is_file():
            problems.append(f"{path}：整个文件不见了（原有 {len(old)} 条简体中文）")
            continue
        try:
            catalog = json.loads(current.read_text())
        except json.JSONDecodeError as error:
            problems.append(f"{path}：不是合法的 JSON（{error}），多半是冲突标记没清干净")
            continue
        new, keys = translations(catalog), catalog.get("strings", {})
        gone = [key for key in old if key not in keys]
        lost = [key for key in old if key in keys and key not in new]
        changed = [key for key in old if key in new and new[key] != old[key]]
        for label, group in (("译文丢了", lost), ("译文被改了", changed)):
            if group:
                problems.append(f"{path}：{label} {len(group)} 条，例如：" + "；".join(repr(key[:60]) for key in group[:5]))
        if gone:
            notes.append(f"{path}：{len(gone)} 个条目整个消失（多半是上游删了文案），例如：" + "；".join(repr(key[:60]) for key in gone[:3]))
    return problems, notes


def check_lines(root, before, upstream):
    """fork 自己加的行（分叉点到合并前的净增行），现在的文件里没有的。"""
    base = git(root, "merge-base", before, upstream, check=False)
    if base is None:
        fail(f"找不到 {before} 与 {upstream} 的分叉点；先 git fetch upstream，或用 --upstream 指定上游分支")
    base, report = base.strip(), []
    for path in git(root, "diff", "--name-only", "--diff-filter=AM", base, before).splitlines():
        if path.endswith(".xcstrings"):
            continue            # 译文单独查，逐行比 JSON 全是噪音
        added = []
        for line in git(root, "diff", "-U0", "--no-color", base, before, "--", path).splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                text = line[1:].strip()
                if len(text) >= SHORTEST and text not in added:
                    added.append(text)
        if not added:
            continue
        current = root / path
        if not current.is_file():
            report.append((path, len(added), len(added), ["（整个文件不见了）"]))
            continue
        present = {line.strip() for line in current.read_text(errors="replace").splitlines()}
        missing = [text for text in added if text not in present]
        if missing:
            report.append((path, len(missing), len(added), missing))
    return base, sorted(report, key=lambda entry: -entry[1])


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--root", default=str(HOME))
    parser.add_argument("--against")
    parser.add_argument("--upstream", default="upstream/main")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    options = parser.parse_args()
    if options.help:
        print(__doc__.strip())
        return 0
    root = Path(options.root).resolve()
    if not DOC.is_file():
        fail(f"找不到清单 {DOC}")
    if not root.is_dir():
        fail(f"找不到工作区 {root}")

    print(f"检查 {root}（清单：{DOC}）")
    bad = check_markers(root)
    print(f"\n一、标记：{'全部通过' if not bad else f'{len(bad)} 处有问题'}")
    for item, message in bad:
        print(f"  [{item}] {message}")

    if not options.against:
        print("\n没有给 --against，译文和“可能丢失的行”没查。")
        return 1 if bad else 0
    if git(root, "rev-parse", "--verify", "-q", f"{options.against}^{{commit}}", check=False) is None:
        fail(f"{options.against} 不是这个仓库里的提交")

    wrong, notes = check_translations(root, options.against)
    print(f"\n二、译文（对照 {options.against}）：{'全部还在' if not wrong else f'{len(wrong)} 处有问题'}")
    for message in wrong + notes:
        print(f"  {message}")

    base, report = check_lines(root, options.against, options.upstream)
    total = sum(entry[1] for entry in report)
    print(f"\n三、可能丢失的行（fork 在 {base[:7]}..{options.against} 加的行，现在没有的）："
          + ("没有" if not report else f"{len(report)} 个文件共 {total} 行，逐个看"))
    for path, missing, added, lines in report:
        print(f"  {path}：{missing}/{added} 行")
        for text in lines if options.verbose else lines[:5]:
            print(f"      {text[:160]}")
        if not options.verbose and len(lines) > 5:
            print(f"      ……还有 {len(lines) - 5} 行（--verbose 全部列出）")

    if bad or wrong:
        return 1
    return 2 if report else 0


if __name__ == "__main__":
    sys.exit(main())
