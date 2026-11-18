"""StageHome（窗口送回原位之后的确认）的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/stage-home"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "Sources/SillHost/StageHome.swift").read_text()
MUTANTS = [
    ("T1 误差变大", "static let tolerance: CGFloat = 2", "static let tolerance: CGFloat = 3"),
    ("T2 误差变小", "static let tolerance: CGFloat = 2", "static let tolerance: CGFloat = 1"),
    ("T3 回读的时刻变了", "[0.15, 0.4, 0.9, 1.6, 2.5]", "[0.15, 0.4, 0.9, 1.6]"),
    ("S1 大小只比宽", "abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance", "abs(a.width - b.width) <= tolerance"),
    ("S2 大小只比高", "abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance", "abs(a.height - b.height) <= tolerance"),
    ("S3 位置只比 x", "abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance", "abs(a.x - b.x) <= tolerance"),
    ("S4 位置只比 y", "abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance", "abs(a.y - b.y) <= tolerance"),
    ("V1 原来的大小不看位置", "return same(now.origin, home.origin) ? .home : .elsewhere", "return .home"),
    ("V2 挪过位置也重写", "return same(now.origin, home.origin) ? .home : .elsewhere", "return same(now.origin, home.origin) ? .home : .wearsStage"),
    ("V3 舞台上的大小不重写", "return same(now.size, staged) ? .wearsStage : .elsewhere", "return .elsewhere"),
    ("V4 别的大小也重写", "return same(now.size, staged) ? .wearsStage : .elsewhere", "return .wearsStage"),
    ("V5 先看舞台的大小", "if same(now.size, home.size) { return same(now.origin, home.origin) ? .home : .elsewhere }\n        return", "if same(now.size, staged) { return .wearsStage }\n        if same(now.size, home.size) { return same(now.origin, home.origin) ? .home : .elsewhere }\n        return"),
    ("E1 一次在原位就结束", "homesInARow >= 2 && look >= 2", "homesInARow >= 1 && look >= 2"),
    ("E2 不等够时间就结束", "homesInARow >= 2 && look >= 2", "homesInARow >= 2"),
    ("E3 等得太久", "homesInARow >= 2 && look >= 2", "homesInARow >= 2 && look >= 3"),
    ("M1 再上舞台时不用上次的原位", "guard let m = remembered, same(found.size, m.staged), !same(m.staged, m.home.size) else { return found }\n        return m.home", "return found"),
    ("M2 不管现在多大都用上次的原位", "guard let m = remembered, same(found.size, m.staged), !same(m.staged, m.home.size) else { return found }", "guard let m = remembered, !same(m.staged, m.home.size) else { return found }"),
    ("M3 原位和舞台一样大时也用上次的", "guard let m = remembered, same(found.size, m.staged), !same(m.staged, m.home.size) else { return found }", "guard let m = remembered, same(found.size, m.staged) else { return found }"),
]

caught = 0
for name, before, after in MUTANTS:
    count = ORIGINAL.count(before)
    if count != 1:
        print(f"{name}：未应用，匹配 {count} 次")
        continue
    source = OUT / "StageHome.swift"
    source.write_text(ORIGINAL.replace(before, after, 1))
    binary = OUT / "mutant"
    binary.unlink(missing_ok=True)
    compiled = subprocess.run(
        ["swiftc", "-O", str(source), str(HERE / "main.swift"), "-o", str(binary)],
        capture_output=True, text=True,
    )
    if compiled.returncode:
        print(f"{name}：编译失败，{compiled.stderr.splitlines()[0] if compiled.stderr else '无错误输出'}")
        continue
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=120)
    failed = [line for line in result.stdout.splitlines() if line.startswith("FAIL")]
    if result.returncode:
        caught += 1
        print(f"{name}：已抓住（{failed[0] if failed else '退出码 ' + str(result.returncode)}）")
    else:
        print(f"{name}：漏过")
# common.sh 根据这个固定格式确认全部变异被抓住。
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
