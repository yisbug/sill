"""横屏顶栏纯规则的单点变异；每个变异都必须让 main.swift 失败。"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / ".build/checks/bar-collapse"
OUT.mkdir(parents=True, exist_ok=True)
ORIGINAL = (ROOT / "iOSClient/BarCollapse.swift").read_text()
MUTANTS = [
    # 所有常量与持久化键。
    ("C1 折叠键错误", 'key = "Sill.barCollapsed"', 'key = "Sill.barCollapse"'),
    ("C2 位置键错误", 'handleKey = "Sill.barHandle"', 'handleKey = "Sill.barPosition"'),
    ("C3 默认在左", 'defaultFraction = 1.0', 'defaultFraction = 0.0'),
    ("C4 按钮过窄", 'buttonWidth: CGFloat = 44', 'buttonWidth: CGFloat = 40'),
    ("C5 图标过宽", 'CGSize(width: 56, height: 26)', 'CGSize(width: 60, height: 26)'),
    ("C6 图标过高", 'CGSize(width: 56, height: 26)', 'CGSize(width: 56, height: 30)'),
    ("C7 点按区过矮", 'touchHeight: CGFloat = 44', 'touchHeight: CGFloat = 26'),
    ("C8 无边距", 'margin: CGFloat = 12', 'margin: CGFloat = 0'),
    # 显示规则的三个输入与读回时的夹取。
    ("H1 忽略存的开关", 'stored && landscape && !tourShown', 'landscape && !tourShown'),
    ("H2 忽略方向", 'stored && landscape && !tourShown', 'stored && !tourShown'),
    ("H3 忽略导览", 'stored && landscape && !tourShown', 'stored && landscape'),
    ("F1 非有限值跑到左端", 'guard stored.isFinite else { return defaultFraction }', 'guard stored.isFinite else { return 0 }'),
    ("F2 未夹住负比例", 'return min(max(stored, 0), 1)', 'return min(stored, 1)'),
    ("F3 未夹住大比例", 'return min(max(stored, 0), 1)', 'return max(stored, 0)'),
    ("F4 正常比例被取整", 'return min(max(stored, 0), 1)', 'return min(max(stored.rounded(), 0), 1)'),
    # 中心范围、插值及折痕避让。
    ("X1 左界没算半宽", 'let low = margin + handleSize.width / 2', 'let low = margin'),
    ("X2 右界没算边距", 'let high = width - margin - handleSize.width / 2', 'let high = width - handleSize.width / 2'),
    ("X3 窄屏放在左端", '(width / 2)...(width / 2)', 'CGFloat(0)...CGFloat(0)'),
    ("X4 中心比例方向反了", 'CGFloat(Self.fraction(stored: fraction))', 'CGFloat(1 - Self.fraction(stored: fraction))'),
    ("X5 中心忽略比例", 'CGFloat(Self.fraction(stored: fraction))', 'CGFloat(0.5)'),
    ("B1 不避折痕", 'guard let fold, x + half > fold.lowerBound, x - half < fold.upperBound else { return x }', 'guard let fold, false else { return x }'),
    ("B2 相交误用中心判断", 'x + half > fold.lowerBound', 'x > fold.lowerBound'),
    ("B3 相交误用中心判断右边", 'x - half < fold.upperBound', 'x < fold.upperBound'),
    ("B4 左侧落位仍压住折痕", 'let left = fold.lowerBound - half', 'let left = fold.lowerBound'),
    ("B5 右侧落位仍压住折痕", 'let right = fold.upperBound + half', 'let right = fold.upperBound'),
    ("B6 不检查两侧放得下", '[left, right].filter { range.contains($0) }', '[left, right]'),
    ("B7 选较远侧", 'abs($0 - x) < abs($1 - x)', 'abs($0 - x) > abs($1 - x)'),
    ("B8 无处可避错误回左界", 'abs($1 - x) } ?? x', 'abs($1 - x) } ?? range.lowerBound'),
    # 拖动、反函数与可见矩形。
    ("D1 拖动未夹住左界", 'return min(max(x, range.lowerBound), range.upperBound)', 'return min(x, range.upperBound)'),
    ("D2 拖动未夹住右界", 'return min(max(x, range.lowerBound), range.upperBound)', 'return max(x, range.lowerBound)'),
    ("D3 拖动不能跟手", 'return min(max(x, range.lowerBound), range.upperBound)', 'return range.lowerBound'),
    ("I1 空范围比例错误", 'guard span > 0 else { return defaultFraction }', 'guard span > 0 else { return 0 }'),
    ("I2 反算未减左界", 'Double((centerX - range.lowerBound) / span)', 'Double(centerX / span)'),
    ("I3 反算未除范围长度", 'Double((centerX - range.lowerBound) / span)', 'Double(centerX - range.lowerBound)'),
    ("I4 反算未夹取", 'return Self.fraction(stored: Double((centerX - range.lowerBound) / span))', 'return Double((centerX - range.lowerBound) / span)'),
    ("R1 矩形横坐标没减半宽", 'x: centerX - handleSize.width / 2', 'x: centerX'),
    ("R2 矩形没有贴顶", 'y: top, width:', 'y: top + 1, width:'),
    ("R3 矩形用了点按高度", 'height: handleSize.height)', 'height: touchHeight)'),
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
