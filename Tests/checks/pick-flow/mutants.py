"""PickFlow（选择排队与画面到达）的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/pick-flow"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "iOSClient/PickFlow.swift").read_text()
MUTANTS = [
    # 两个等待上限。
    ("W1 等结果只等 5 秒", 'answerWait: TimeInterval { 8 }', 'answerWait: TimeInterval { 5 }'),
    ("W2 等画面的时间变了", 'pictureWait: TimeInterval { 9 }', 'pictureWait: TimeInterval { 12 }'),
    # 选择：路上有一次时不发，只留最新的；重选当前源不跟踪。
    ("P1 路上有一次也发（原问题）", '                queued = source\n                wanted = Wanted(source: source, pickedAt: now)\n            }\n            return false',
     '                queued = source\n                wanted = Wanted(source: source, pickedAt: now)\n            }\n            return true'),
    ("P2 选回路上的那个时没作废排队", '                // 又选回了路上的那一个：不用再发，排队的作废。\n                queued = nil', '                // 又选回了路上的那一个：不用再发，排队的作废。'),
    ("P3 选回路上的那个时重置了选的时刻", 'if wanted?.source != source {\n                    wanted = Wanted(source: source, pickedAt: now, sentAt: flight.sentAt',
     'if true {\n                    wanted = Wanted(source: source, pickedAt: now, sentAt: flight.sentAt'),
    ("P4 选回路上的那个时丢了已到的关键帧", 'keyframeAt: keyframe(since: flight.sentAt))', 'keyframeAt: nil)'),
    ("P5 排队的被当成已发出", 'wanted = Wanted(source: source, pickedAt: now)\n            }', 'wanted = Wanted(source: source, pickedAt: now, sentAt: now)\n            }'),
    ("P6 重选当前源也跟踪", '        if source == active {\n            wanted = nil\n            return true\n        }\n', ''),
    ("P7 出发的源记错", 'flight = Flight(source: source, from: active, sentAt: now)\n        wanted', 'flight = Flight(source: source, from: source, sentAt: now)\n        wanted'),
    # 列表：之前的列表继续等；有结果后发排队的；没成就放下。
    ("L1 之前的列表也当成结果", 'if active == f.from { return (nil, nil) }', 'if false { return (nil, nil) }'),
    ("L2 有结果后不发排队的", 'if next != active {       // 它还在', 'if false {       // 它还在'),
    ("L3 排着的窗口不在了还留着排队", 'if queued == w.source { queued = nil }', 'if queued == w.source { _ = queued }'),
    ("L4 排着的就是当前源还发", 'if next != active {       // 它还在', 'if true {       // 它还在'),
    ("L5 排队的发出时没记发出时刻", "                if wanted?.source == next { wanted?.sentAt = now }\n                return (next, nil)\n            }\n            // 排着的",
     "                return (next, nil)\n            }\n            // 排着的"),
    ("L6 排队的从错的源出发", 'flight = Flight(source: next, from: active, sentAt: now)\n                if wanted?.source == next { wanted?.sentAt = now }\n                return (next, nil)\n            }\n            // 排着的',
     'flight = Flight(source: next, from: f.from, sentAt: now)\n                if wanted?.source == next { wanted?.sentAt = now }\n                return (next, nil)\n            }\n            // 排着的'),
    ("L7 Mac 已在串流排着的那个时不认之前的关键帧", 'let seen = keyframe(since: f.sentAt)', 'let seen: TimeInterval? = nil'),
    ("L8 没成的选择还占着画面", '            wanted = nil            // 这次选择没成', '            // 这次选择没成'),
    ("L9 没在路上时被别处换掉还等", 'if let w = wanted, w.source != active { wanted = nil }', 'if let w = wanted, w.source != active { _ = w }'),
    ("L10 窗口不在了还等它", 'if let w = wanted, !exists(w.source) {\n            wanted = nil', 'if let w = wanted, !exists(w.source) {'),
    ("L11 列表到了不算 Mac 确认", '        w.confirmedAt = now\n        if !hasPicture', '        if !hasPicture'),
    ("L12 没有画面的源也等关键帧", 'if !hasPicture(w.source), w.keyframeAt == nil { w.keyframeAt = now }', 'if false, w.keyframeAt == nil { w.keyframeAt = now }'),
    ("L13 有画面的源不等关键帧", 'if !hasPicture(w.source), w.keyframeAt == nil { w.keyframeAt = now }', 'if w.keyframeAt == nil { w.keyframeAt = now }'),
    # 关键帧。
    ("K1 发出之前的关键帧也算", 'receivedAt >= sentAt, w.keyframeAt == nil', 'w.keyframeAt == nil'),
    ("K2 后来的关键帧改了时刻", 'receivedAt >= sentAt, w.keyframeAt == nil', 'receivedAt >= sentAt'),
    ("K3 不记最近的关键帧", '        lastKeyframeAt = receivedAt\n', ''),
    ("K4 只有关键帧就算画面到了", 'let confirmedAt = w.confirmedAt, let keyframeAt', 'let confirmedAt = w.keyframeAt, let keyframeAt'),
    ("K5 之前的关键帧不看先后", 'lastKeyframeAt.flatMap { $0 >= sentAt ? $0 : nil }', 'lastKeyframeAt'),
    # 到点。
    ("E1 没到点就放下", 'guard now - f.sentAt >= Self.answerWait else { return (nil, false) }', 'guard now - f.sentAt >= 0 else { return (nil, false) }'),
    ("E2 到点不发排队的", '                if next != active {\n                    flight = Flight(source: next, from: active, sentAt: now)', '                if false {\n                    flight = Flight(source: next, from: active, sentAt: now)'),
    ("E3 到点发了当前源", '                if next != active {\n                    flight = Flight(source: next, from: active, sentAt: now)', '                if true {\n                    flight = Flight(source: next, from: active, sentAt: now)'),
    ("E4 到点后还占着画面", '            wanted = nil\n            return (nil, true)\n        }\n        if let w = wanted', '            return (nil, true)\n        }\n        if let w = wanted'),
    ("E5 等画面不设上限", 'now - sentAt >= Self.pictureWait {\n            wanted = nil', 'now - sentAt >= Self.pictureWait, false {\n            wanted = nil'),
    ("E6 期限用错了上限", 'if let f = flight { return f.sentAt + Self.answerWait }', 'if let f = flight { return f.sentAt + Self.pictureWait }'),
    ("E7 等画面时没有期限", 'if let sentAt = wanted?.sentAt { return sentAt + Self.pictureWait }', 'if let sentAt = wanted?.sentAt, false { return sentAt + Self.pictureWait }'),
    # 耗时与重置。
    ("D1 总耗时没取较晚的", 'total: max(confirmedAt, keyframeAt) - w.pickedAt', 'total: min(confirmedAt, keyframeAt) - w.pickedAt'),
    ("D2 总耗时从发出算", 'total: max(confirmedAt, keyframeAt) - w.pickedAt', 'total: max(confirmedAt, keyframeAt) - sentAt'),
    ("D3 排队时间算错", 'queued: max(0, sentAt - w.pickedAt)', 'queued: 0'),
    ("D4 列表与关键帧对调", 'listAfterSend: confirmedAt - sentAt, keyframeAfterSend: keyframeAt - sentAt', 'listAfterSend: keyframeAt - sentAt, keyframeAfterSend: confirmedAt - sentAt'),
    ("D5 完成后还占着画面", '        wanted = nil\n        return Done(', '        return Done('),
    ("D6 毫秒没取整", 'Int((seconds * 1000).rounded())', 'Int(seconds * 1000)'),
    ("R1 重置留着关键帧", '        wanted = nil\n        lastKeyframeAt = nil\n', '        wanted = nil\n'),
    ("R2 重置留着排队的", '        flight = nil\n        queued = nil\n        wanted = nil\n        lastKeyframeAt', '        flight = nil\n        wanted = nil\n        lastKeyframeAt'),
]

caught = 0
for name, before, after in MUTANTS:
    count = ORIGINAL.count(before)
    if count != 1:
        print(f"{name}：未应用，匹配 {count} 次")
        continue
    source = OUT / "PickFlow.swift"
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
