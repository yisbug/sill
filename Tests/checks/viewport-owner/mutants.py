"""ViewportOwner（几台设备时窗口按哪一台的面板）的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/viewport-owner"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "Sources/SillHost/ViewportOwner.swift").read_text()
MUTANTS = [
    ("R1 别的设备发来视口就抢走", "if owner == nil || owner.flatMap({ viewports[$0] }) == nil { owner = id }", "owner = id"),
    ("R2 没有主人时不认第一个发视口的", "if owner == nil || owner.flatMap({ viewports[$0] }) == nil { owner = id }", "if false { owner = id }"),
    ("R3 收到视口不记", "        let before = chosen\n        viewports[id] = viewport\n", "        let before = chosen\n"),
    ("R4 收到视口总说变了", "if owner == nil || owner.flatMap({ viewports[$0] }) == nil { owner = id }\n        return chosen != before", "if owner == nil || owner.flatMap({ viewports[$0] }) == nil { owner = id }\n        return true"),
    ("U1 操作了也不换主人", "        let before = chosen\n        owner = id\n        return chosen != before", "        let before = chosen\n        return chosen != before"),
    ("U2 没发过视口的设备也成了主人", "guard owner != id, viewports[id] != nil else { return false }", "guard owner != id else { return false }"),
    ("U3 换主人总说变了", "        owner = id\n        return chosen != before\n    }\n\n    /// `id` 断开了", "        owner = id\n        return true\n    }\n\n    /// `id` 断开了"),
    ("U4 不记用过的先后", "        recent.removeAll { $0 == id }\n        recent.append(id)\n", ""),
    ("U5 用过的先后记反了", "        recent.append(id)\n", "        recent.insert(id, at: 0)\n"),
    ("L1 走了的设备的视口还留着", "        let before = chosen\n        viewports[id] = nil\n", "        let before = chosen\n"),
    ("L2 走了的设备还算用过", "        viewports[id] = nil\n        recent.removeAll { $0 == id }\n", "        viewports[id] = nil\n"),
    ("L3 主人走了不换人", "        if owner == id {\n            owner = recent.last", "        if false {\n            owner = recent.last"),
    ("L4 别的设备走了也换人", "        if owner == id {\n            owner = recent.last", "        if true {\n            owner = recent.last"),
    ("L5 换成最早用过的", "owner = recent.last { viewports[$0] != nil }", "owner = recent.first { viewports[$0] != nil }"),
    ("L6 换成没有视口的设备", "owner = recent.last { viewports[$0] != nil }", "owner = recent.last { _ in true }"),
    ("L7 不看给的顺序", "?? order.first { viewports[$0] != nil } ?? viewports.keys.first", "?? viewports.keys.sorted { \"\\($0)\" < \"\\($1)\" }.first"),
    ("L8 顺序里没视口的也选", "?? order.first { viewports[$0] != nil }", "?? order.first"),
    ("X1 重置留着视口", "        viewports = [:]\n        recent = []\n        owner = nil", "        recent = []\n        owner = nil"),
    ("X2 重置留着先后", "        viewports = [:]\n        recent = []\n        owner = nil", "        viewports = [:]\n        owner = nil"),
    ("X3 重置留着主人", "        viewports = [:]\n        recent = []\n        owner = nil", "        viewports = [:]\n        recent = []"),
]

caught = 0
for name, before, after in MUTANTS:
    count = ORIGINAL.count(before)
    if count != 1:
        print(f"{name}：未应用，匹配 {count} 次")
        continue
    source = OUT / "ViewportOwner.swift"
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
