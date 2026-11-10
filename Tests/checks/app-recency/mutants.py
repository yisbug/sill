"""AppRecency 的单点变异；只有编译成功且用例失败才算抓到。"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "app-recency")
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(ROOT, "iOSClient", "AppRecency.swift")) as source:
    original = source.read()

MUTANTS = [
    ("A1 当前应用不置顶", "let activeApp = windows.first { $0.id == active }?.appID", "let activeApp: String? = nil; _ = active"),
    ("A2 应用时间升序", "            return lhs == rhs ? left.offset < right.offset : lhs > rhs\n        }", "            return lhs == rhs ? left.offset < right.offset : lhs < rhs\n        }"),
    ("A3 未用应用顺序反转", "            return lhs == rhs ? left.offset < right.offset : lhs > rhs\n        }", "            return lhs == rhs ? left.offset > right.offset : lhs > rhs\n        }"),
    ("A4 未用应用排到已用之前", 'record.apps[left.element] ?? -.infinity', 'record.apps[left.element] ?? .infinity'),
    ("W1 当前窗口错误参与轮换候选", "members.filter { $0.id != active }.enumerated().sorted", "members.enumerated().sorted"),
    ("W2 错按 Mac 相邻窗口轮换", "}.first?.element.id ?? active", "}.first.map { _ in ids[(ids.firstIndex(of: active)! + 1) % ids.count] } ?? active"),
    ("W3 非当前应用总选 Mac 首窗口", "}.first!.element.id", "}.map { _ in members[0].id }.first!"),
    ("W4 窗口时间升序", "return lhs == rhs ? left.offset < right.offset : lhs > rhs\n                }.first!.element.id", "return lhs == rhs ? left.offset < right.offset : lhs < rhs\n                }.first!.element.id"),
    ("W5 不返回同应用其他窗口", "windowIDs: ids, targetID: target", "windowIDs: [ids[0]], targetID: target"),
    ("R1 使用时不记应用", "record.apps[window.appID] = time", "record.apps[window.appID] = 0"),
    ("R2 使用时不记窗口", "record.windows[window.id] = time", "record.windows[window.id] = 0"),
    ("R3 无 bundle ID 应用错误合并", 'bundleID.isEmpty ? "name:" + appName : bundleID', 'bundleID.isEmpty ? "name:" : bundleID'),
    ("S1 存储键前缀漂移", '"Sill.appRecency." + mac', '"Sill.windowOrder." + mac'),
    ("S2 不隔离不同 Mac", '"Sill.appRecency." + mac', '"Sill.appRecency."'),
    ("S3 保存时丢失应用记录", 'defaults.set(["apps": apps, "windows": windows]', 'defaults.set(["apps": [String: Double](), "windows": windows]'),
    ("S4 读取时丢失窗口记录", "return Record(apps: apps, windows: windows)", "return Record(apps: apps, windows: [:])"),
]
caught = 0
for name, before, after in MUTANTS:
    if original.count(before) != 1:
        print(f"{name}: 未应用（模式出现 {original.count(before)} 次，预期 1）")
        continue
    path = os.path.join(OUT, "AppRecency.swift")
    with open(path, "w") as source:
        source.write(original.replace(before, after, 1))
    binary = os.path.join(OUT, "mutant")
    compile_result = subprocess.run(
        ["swiftc", "-O", "-module-cache-path", os.path.join(OUT, "ModuleCache"), path, os.path.join(HERE, "main.swift"), "-o", binary],
        capture_output=True, text=True,
    )
    if compile_result.returncode:
        print(f"{name}: 编译失败（不计为抓到）：{compile_result.stderr.splitlines()[0]}")
        continue
    result = subprocess.run([binary], capture_output=True, text=True, timeout=60)
    failures = [line for line in result.stdout.splitlines() if line.startswith("FAIL")]
    if result.returncode and failures:
        caught += 1
        print(f"{name}: 已抓到（{failures[0]}）")
    else:
        print(f"{name}: 未抓到（退出码 {result.returncode}）")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
