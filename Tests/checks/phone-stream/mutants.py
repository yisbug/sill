"""iPhone 串流界面纯规则的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/phone-stream"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "iOSClient/PhoneStream.swift").read_text()
EXTRA = [str(ROOT / "Sources/StreamProtocol/TextScale.swift"), str(ROOT / "Sources/StreamProtocol/Switcher.swift"), str(ROOT / "Sources/StreamProtocol/StreamMessage.swift")]
MUTANTS = [
    ("L1 非 iPhone 也锁横屏", 'phone && streamShown', 'streamShown'),
    ("L2 iPhone 不在串流界面也锁", 'phone && streamShown', 'phone'),
    ("L3 谁都不锁", 'phone && streamShown', 'false'),
    ("D1 iPhone 看尺寸", 'phone || size.width > size.height', 'size.width > size.height'),
    ("D2 非 iPhone 总横屏", 'phone || size.width > size.height', 'true'),
    ("D3 方形算横屏", 'size.width > size.height }', 'size.width >= size.height }'),
    ("V1 iPhone 竖屏也发", '!phone || screen.width > screen.height', 'true'),
    ("V2 非 iPhone 也等横屏", '!phone || screen.width > screen.height', 'screen.width > screen.height'),
    ("V3 iPhone 方形也发", 'screen.width > screen.height }', 'screen.width >= screen.height }'),
    ("K1 键错误", 'textScaleKey = "Sill.textScale"', 'textScaleKey = "Sill.textSize"'),
    ("F1 iPhone 默认值错误", 'phone ? 0.75 : nil', 'phone ? 1.0 : nil'),
    ("F2 iPad 默认值错误", 'phone ? 0.75 : nil', 'phone ? 0.75 : 1.0'),
    ("F3 默认不看设备", 'phone ? 0.75 : nil', '0.75'),
    ("R1 不读 NSNumber", 'case let number as NSNumber: value = number.doubleValue', 'case let number as NSNumber: return defaultTextScale(phone: phone)'),
    ("R2 不读字符串", 'value = parsed', 'return defaultTextScale(phone: phone)'),
    ("R3 字符串非法也贴档", 'else { return defaultTextScale(phone: phone) }\n            value = parsed', 'else { return 0.5 }\n            value = parsed'),
    ("R4 非有限值不回默认", 'guard value.isFinite else { return defaultTextScale(phone: phone) }', 'guard !value.isNaN else { return defaultTextScale(phone: phone) }'),
    ("R5 Off 不读成 nil", 'if value == TextScale.off { return nil }', ''),
    ("R6 取最远一档", 'abs($0 - value) < abs($1 - value)', 'abs($0 - value) > abs($1 - value)'),
    ("R7 不贴档", 'return TextScale.scales.min { abs($0 - value) < abs($1 - value) }', 'return value'),
    ("R8 不回默认的其他类型", 'default: return defaultTextScale(phone: phone)', 'default: return nil'),
    ("W1 Off 写 0", 'scale ?? TextScale.off', 'scale ?? 0'),
    ("W2 缩放写错", 'static func stored(for scale: Double?) -> Double { scale ?? TextScale.off }', 'static func stored(for scale: Double?) -> Double { (scale ?? TextScale.off) + 0.01 }'),
    ("T1 标题错误", 'String(localized: "Text Size"', 'String(localized: "Text size"'),
    ("T2 脚注错误", 'It is the same setting as Aa in the toolbar.', 'It is a separate setting.'),
    # 灵动岛一侧留黑边。
    ("I1 灵动岛左右反了", 'return landscapeRight ? .left : .right', 'return landscapeRight ? .right : .left'),
    ("I2 非 iPhone 也有灵动岛一侧", 'guard phone, let landscapeRight else { return nil }', 'guard let landscapeRight else { return nil }'),
    ("I3 方向未知当成在左", 'guard phone, let landscapeRight else { return nil }', 'guard phone else { return nil }\n        let landscapeRight = landscapeRight ?? true'),
    ("I4 灵动岛在左却铺了左侧", 'case .left?: return (false, true)', 'case .left?: return (true, true)'),
    ("I5 灵动岛在左却没铺右侧", 'case .left?: return (false, true)', 'case .left?: return (false, false)'),
    ("I6 灵动岛在右却铺了右侧", 'case .right?: return (true, false)', 'case .right?: return (true, true)'),
    ("I7 灵动岛在右却没铺左侧", 'case .right?: return (true, false)', 'case .right?: return (false, false)'),
    ("I8 方向未知时两侧都铺", 'case nil: return (false, false)', 'case nil: return (true, true)'),
    ("I9 非 iPhone 不铺", 'guard phone else { return (true, true) }', 'guard phone else { return (false, false) }'),
    ("I10 iPhone 也两侧都铺", 'guard phone else { return (true, true) }\n        switch island', 'guard false else { return (true, true) }\n        switch island'),
]

caught = 0
for name, before, after in MUTANTS:
    count = ORIGINAL.count(before)
    if count != 1:
        print(f"{name}：未应用，匹配 {count} 次")
        continue
    source = OUT / "PhoneStream.swift"
    source.write_text(ORIGINAL.replace(before, after, 1))
    binary = OUT / "mutant"
    binary.unlink(missing_ok=True)
    compiled = subprocess.run(
        ["swiftc", "-O", str(source), *EXTRA, str(HERE / "main.swift"), "-o", str(binary)],
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
