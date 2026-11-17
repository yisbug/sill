import Foundation
import CoreGraphics

typealias B = BarCollapse
var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("通过 \(name)") }
    else { fails += 1; print("FAIL \(name)") }
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-9 }

// 常量逐项检查，避免同一错误同时改变预期值和实现。
check("折叠状态键", B.key == "Sill.barCollapsed")
check("顶边位置键", B.handleKey == "Sill.barHandle")
check("默认在最右", B.defaultFraction == 1)
check("折叠按钮宽 44", B.buttonWidth == 44)
check("图标可见尺寸 56 × 26", B.handleSize == CGSize(width: 56, height: 26))
check("点按高度 44", B.touchHeight == 44)
check("左右边距 12", B.margin == 12)
for stored in [false, true] {
    for landscape in [false, true] {
        for tour in [false, true] {
            check("显示组合 \(stored) / \(landscape) / \(tour)",
                  B.hidesBar(stored: stored, landscape: landscape, tourShown: tour) == (stored && landscape && !tour))
        }
    }
}
check("NaN 用默认位置", B.fraction(stored: .nan) == 1)
check("正无穷用默认位置", B.fraction(stored: .infinity) == 1)
check("负无穷用默认位置", B.fraction(stored: -.infinity) == 1)
check("负比例夹到左端", B.fraction(stored: -0.4) == 0)
check("大比例夹到右端", B.fraction(stored: 1.4) == 1)
check("正常比例保持", B.fraction(stored: 0.37) == 0.37)
check("两端比例保持", B.fraction(stored: 0) == 0 && B.fraction(stored: 1) == 1)

check("中心左端为 40", B.centerX(fraction: 0, width: 400) == 40)
check("中心右端为 360", B.centerX(fraction: 1, width: 400) == 360)
check("中心中点为 200", B.centerX(fraction: 0.5, width: 400) == 200)
check("非中点线性插值", B.centerX(fraction: 0.25, width: 400) == 120)
check("中心比例先夹取", B.centerX(fraction: -1, width: 400) == 40 && B.centerX(fraction: 2, width: 400) == 360)
check("中心非有限比例用默认", B.centerX(fraction: .nan, width: 400) == 360)
check("窄屏放中点", B.centerX(fraction: 0, width: 60) == 30 && B.centerX(fraction: 1, width: 60) == 30)
check("零宽屏放中点", B.centerX(fraction: 0.5, width: 0) == 0)
check("恰好放下只有一个位置", B.centerX(fraction: 0.2, width: 80) == 40)

func at(_ x: CGFloat, width: CGFloat = 400, fold: ClosedRange<CGFloat>) -> CGFloat {
    B.centerX(fraction: Double((x - 40) / (width - 80)), width: width, fold: fold)
}
check("折痕相交时靠左落位", at(180, fold: 170...210) == 142)
check("折痕相交时靠右落位", at(200, fold: 170...210) == 238)
check("折痕等距时靠左落位", at(190, fold: 170...210) == 142)
check("近侧放不下改放右侧", at(40, fold: 20...100) == 128)
check("近侧放不下改放左侧", at(360, fold: 300...380) == 272)
check("两侧都放不下保持原位", at(200, fold: 20...380) == 200)
check("与折痕不相交保持原位", at(100, fold: 170...210) == 100)
check("紧贴折痕左边保持原位", at(142, fold: 170...210) == 142)
check("紧贴折痕右边保持原位", at(238, fold: 170...210) == 238)
check("窄屏折痕无处可避仍取中点", B.centerX(fraction: 0.5, width: 60, fold: 20...40) == 30)

check("拖动越左夹取", B.dragged(to: -100, width: 400) == 40)
check("拖动越右夹取", B.dragged(to: 900, width: 400) == 360)
check("拖动中间保持", B.dragged(to: 153, width: 400) == 153)
check("窄屏拖动取中点", B.dragged(to: -10, width: 60) == 30 && B.dragged(to: 100, width: 60) == 30)
check("反算左端", B.fraction(centerX: 40, width: 400) == 0)
check("反算右端", B.fraction(centerX: 360, width: 400) == 1)
check("反算非中点", B.fraction(centerX: 120, width: 400) == 0.25)
check("反算越界夹取", B.fraction(centerX: -100, width: 400) == 0 && B.fraction(centerX: 900, width: 400) == 1)
check("窄屏反算用默认", B.fraction(centerX: 30, width: 60) == 1)
check("恰好放下反算用默认", B.fraction(centerX: 40, width: 80) == 1)
check("图标矩形尺寸与位置", B.handleRect(centerX: 123, top: 7) == CGRect(x: 95, y: 7, width: 56, height: 26))
check("图标矩形可以贴顶边", B.handleRect(centerX: 40, top: 0).minY == 0)

// 固定种子使随机失败可以复现；每一组都验证边界、单调性、反函数及折痕避让。
var seed: UInt64 = 0xBA7C011A95E
func unit() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(UInt64(1) << 53)
}
var ranged = true, monotonic = true, inverseFraction = true, inverseCenter = true
var foldedRanged = true, foldedFree = true, unchangedWhenFree = true, unchangedWhenBlocked = true
for _ in 0..<5_000 {
    let width = CGFloat(81 + unit() * 4_000)
    let a = unit(), b = unit()
    let f = min(a, b), g = max(a, b)
    let x = B.centerX(fraction: f, width: width)
    let y = B.centerX(fraction: g, width: width)
    let low: CGFloat = 40, high = width - 40
    ranged = ranged && x >= low && x <= high && y >= low && y <= high
    monotonic = monotonic && x <= y
    inverseFraction = inverseFraction && abs(B.fraction(centerX: x, width: width) - f) < 1e-9
    let finger = CGFloat(unit() * Double(width + 200) - 100)
    let clamped = min(max(finger, low), high)
    inverseCenter = inverseCenter && near(B.centerX(fraction: B.fraction(centerX: finger, width: width), width: width), clamped)

    let lower = CGFloat(unit() * Double(width + 100) - 50)
    let upper = lower + CGFloat(unit() * Double(width))
    let result = B.centerX(fraction: f, width: width, fold: lower...upper)
    let intersects = x + 28 > lower && x - 28 < upper
    let canAvoid = lower - 28 >= low || upper + 28 <= high
    foldedRanged = foldedRanged && result >= low && result <= high
    if intersects && canAvoid {
        foldedFree = foldedFree && (result + 28 <= lower + 1e-9 || result - 28 >= upper - 1e-9)
    }
    if !intersects { unchangedWhenFree = unchangedWhenFree && result == x }
    if intersects && !canAvoid { unchangedWhenBlocked = unchangedWhenBlocked && result == x }
}
check("随机 5,000 组中心始终在范围内", ranged)
check("随机 5,000 组比例单调", monotonic)
check("随机 5,000 组中心反算比例误差小于 1e-9", inverseFraction)
check("随机 5,000 组比例还原夹取后的中心误差小于 1e-9", inverseCenter)
check("随机 5,000 组避折痕后仍在范围内", foldedRanged)
check("随机 5,000 组可避让时结果不与折痕相交", foldedFree)
check("随机 5,000 组未相交时不挪动", unchangedWhenFree)
check("随机 5,000 组无处可避时不挪动", unchangedWhenBlocked)
print("\(passes) 项通过，\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
