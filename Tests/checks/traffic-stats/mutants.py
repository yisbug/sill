"""流量统计纯规则的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/traffic-stats"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "iOSClient/TrafficStats.swift").read_text()
MUTANTS = [
    ("K1 存储键错误", 'key = "Sill.trafficStats"', 'key = "Sill.traffic"'),
    ("K2 小时只留 7 天", 'keepHours: TimeInterval = 8 * 24 * 3600', 'keepHours: TimeInterval = 7 * 24 * 3600'),
    ("K3 天只留 365 天", 'keepDays = 400', 'keepDays = 365'),
    ("A1 负数照记", 'Int64(max(0, received))', 'Int64(received)'),
    ("A2 发出的负数照记", 'Int64(max(0, sent))', 'Int64(sent)'),
    ("A3 0 也记", 'guard usage.total > 0 else { return }', 'guard usage.total >= 0 else { return }'),
    ("A4 开始时刻被覆盖", 'if since == nil { since = date }', 'since = date'),
    ("A5 天按小时切", 'let day = Self.stamp(calendar.startOfDay(for: date))', 'let day = Self.stamp(Self.hourStart(date, calendar))'),
    ("A6 小时桶覆盖不累加", 'hours[hour, default: Usage()] = hours[hour, default: Usage()] + usage', 'hours[hour] = usage'),
    ("A7 天桶覆盖不累加", 'days[day, default: Usage()] = days[day, default: Usage()] + usage', 'days[day] = usage'),
    ("A8 累计不加", 'total = total + usage', 'total = usage'),
    ("A9 不清理", '        prune(now: date, calendar: calendar)\n', '\n'),
    ("U1 收发相加写错", 'Usage(received: a.received + b.received, sent: a.sent + b.sent)', 'Usage(received: a.received + b.received, sent: a.sent)'),
    ("U2 合计只算收到", 'var total: Int64 { received + sent }', 'var total: Int64 { received }'),
    ("P1 小时边界含等号", 'hours = hours.filter { $0.key > oldestHour }', 'hours = hours.filter { $0.key >= oldestHour }'),
    ("P2 天多留一天", 'value: -(Self.keepDays - 1), to: today', 'value: -Self.keepDays, to: today'),
    ("P3 天边界不含等号", 'days = days.filter { $0.key >= cut }', 'days = days.filter { $0.key > cut }'),
    ("L1 近 N 小时不含当前", '(0..<count).reversed().compactMap { back in\n            guard let start = calendar.date(byAdding: .hour, value: -back,', '(1...count).reversed().compactMap { back in\n            guard let start = calendar.date(byAdding: .hour, value: -back,'),
    ("L2 近 N 小时从晚到早", 'return (0..<count).reversed().compactMap { back in\n            guard let start = calendar.date(byAdding: .hour', 'return (0..<count).compactMap { back in\n            guard let start = calendar.date(byAdding: .hour'),
    ("L3 近 N 天不含今天", 'guard let start = calendar.date(byAdding: .day, value: -back, to: today)', 'guard let start = calendar.date(byAdding: .day, value: -back - 1, to: today)'),
    ("L4 没数据的小时丢掉", 'usage: hours[Self.stamp(start)] ?? Usage())', 'usage: hours[Self.stamp(start)] ?? Usage(received: 1))'),
    ("S1 近 7 天只算 6 天", 'lastDays(7, now: now, calendar: calendar)', 'lastDays(6, now: now, calendar: calendar)'),
    ("S2 今天取错", 'days[Self.stamp(calendar.startOfDay(for: now))] ?? Usage()', 'hours[Self.stamp(Self.hourStart(now, calendar))] ?? Usage()'),
    ("D1 读不出来时崩溃", 'guard let data, let stats = try? JSONDecoder().decode(TrafficStats.self, from: data) else { return TrafficStats() }', 'let stats = try! JSONDecoder().decode(TrafficStats.self, from: data!)'),
]

caught = 0
for name, before, after in MUTANTS:
    count = ORIGINAL.count(before)
    if count != 1:
        print(f"{name}：未应用，匹配 {count} 次")
        continue
    source = OUT / "BarCollapse.swift"
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
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    failed = [line for line in result.stdout.splitlines() if line.startswith("FAIL")]
    if result.returncode:
        caught += 1
        print(f"{name}：已抓住（{failed[0] if failed else '退出码 ' + str(result.returncode)}）")
    else:
        print(f"{name}：漏过")
# common.sh 根据这个固定格式确认全部变异被抓住。
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
