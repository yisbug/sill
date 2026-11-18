import Foundation
import CoreGraphics

typealias P = PhoneStream
var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("通过 \(name)") }
    else { fails += 1; print("FAIL \(name)") }
}

let landscape = CGSize(width: 844, height: 390)
let portrait = CGSize(width: 390, height: 844)
let square = CGSize(width: 500, height: 500)

// 持久化键与默认值。
check("缩放键", P.textScaleKey == "Sill.textScale")
check("iPhone 默认 0.75", P.defaultTextScale(phone: true) == 0.75)
check("非 iPhone 默认 Off", P.defaultTextScale(phone: false) == nil)

// 强制横屏：只有 iPhone 且串流界面显示。
for phone in [false, true] {
    for shown in [false, true] {
        check("横屏锁 \(phone) / \(shown)", P.locksLandscape(phone: phone, streamShown: shown) == (phone && shown))
    }
}

// 横屏布局：iPhone 不看尺寸；其他设备宽大于高。
for size in [landscape, portrait, square] {
    check("iPhone 总画横屏 \(size)", P.drawsLandscape(phone: true, size: size))
}
check("非 iPhone 横屏尺寸", P.drawsLandscape(phone: false, size: landscape))
check("非 iPhone 竖屏尺寸", !P.drawsLandscape(phone: false, size: portrait))
check("非 iPhone 方形尺寸", !P.drawsLandscape(phone: false, size: square))

// 视口：iPhone 屏幕还是竖的、方的时不发；横的发；其他设备总发。
check("iPhone 竖屏不发", !P.sendsViewport(phone: true, screen: portrait))
check("iPhone 方形不发", !P.sendsViewport(phone: true, screen: square))
check("iPhone 横屏发", P.sendsViewport(phone: true, screen: landscape))
for size in [landscape, portrait, square] {
    check("非 iPhone 总发 \(size)", P.sendsViewport(phone: false, screen: size))
}

// 灵动岛一侧留黑边（本 fork）。
check("iPhone，机身顶部朝左：灵动岛在左", P.islandSide(phone: true, landscapeRight: true) == .left)
check("iPhone，机身顶部朝右：灵动岛在右", P.islandSide(phone: true, landscapeRight: false) == .right)
check("iPhone，方向还不知道：不知道在哪", P.islandSide(phone: true, landscapeRight: nil) == nil)
check("非 iPhone 没有灵动岛一侧", P.islandSide(phone: false, landscapeRight: true) == nil && P.islandSide(phone: false, landscapeRight: false) == nil
      && P.islandSide(phone: false, landscapeRight: nil) == nil)
check("灵动岛在左：只铺右侧", P.fills(phone: true, island: .left) == (false, true))
check("灵动岛在右：只铺左侧", P.fills(phone: true, island: .right) == (true, false))
check("iPhone 方向未知：两侧都不铺", P.fills(phone: true, island: nil) == (false, false))
check("非 iPhone 两侧都铺", P.fills(phone: false, island: nil) == (true, true) && P.fills(phone: false, island: .left) == (true, true)
      && P.fills(phone: false, island: .right) == (true, true))

// 读回：没存。
check("没存 iPhone", P.textScale(stored: nil, phone: true) == 0.75)
check("没存 iPad", P.textScale(stored: nil, phone: false) == nil)
// Off 的存值。
for phone in [false, true] {
    check("Off 存值 \(phone)", P.textScale(stored: TextScale.off, phone: phone) == nil)
    check("Off 字符串 \(phone)", P.textScale(stored: "0.25", phone: phone) == nil)
    // 每一档读回自己，数字与字符串形式一致。
    for scale in TextScale.scales {
        check("档位 \(scale) 数字 \(phone)", P.textScale(stored: scale, phone: phone) == scale)
        check("档位 \(scale) 字符串 \(phone)", P.textScale(stored: "\(scale)", phone: phone) == scale)
        check("档位 \(scale) NSNumber \(phone)", P.textScale(stored: NSNumber(value: scale), phone: phone) == scale)
    }
    // 贴最近一档。
    check("0.6 贴 0.5 \(phone)", P.textScale(stored: 0.6, phone: phone) == 0.5)
    check("0.7 贴 0.75 \(phone)", P.textScale(stored: 0.7, phone: phone) == 0.75)
    check("1.1 贴 1 \(phone)", P.textScale(stored: 1.1, phone: phone) == 1.0)
    check("1.2 贴 1.25 \(phone)", P.textScale(stored: 1.2, phone: phone) == 1.25)
    check("过大贴 1.5 \(phone)", P.textScale(stored: 9.0, phone: phone) == 1.5)
    check("过小的非 Off 值贴 0.5 \(phone)", P.textScale(stored: 0.1, phone: phone) == 0.5)
    check("负数贴 0.5 \(phone)", P.textScale(stored: -3.0, phone: phone) == 0.5)
}
// 非法值按没存处理。
for phone in [false, true] {
    let fallback = P.defaultTextScale(phone: phone)
    check("NaN 回默认 \(phone)", P.textScale(stored: Double.nan, phone: phone) == fallback)
    check("无穷回默认 \(phone)", P.textScale(stored: Double.infinity, phone: phone) == fallback)
    check("乱字符串回默认 \(phone)", P.textScale(stored: "big", phone: phone) == fallback)
    check("空字符串回默认 \(phone)", P.textScale(stored: "", phone: phone) == fallback)
    check("nan 字符串回默认 \(phone)", P.textScale(stored: "nan", phone: phone) == fallback)
    check("其他类型回默认 \(phone)", P.textScale(stored: [1], phone: phone) == fallback)
}
check("字符串前后空格", P.textScale(stored: " 1.25 ", phone: false) == 1.25)

// 写入与往返。
check("Off 写 0.25", P.stored(for: nil) == TextScale.off)
for scale in TextScale.scales {
    check("写入 \(scale)", P.stored(for: scale) == scale)
    for phone in [false, true] {
        check("往返 \(scale) \(phone)", P.textScale(stored: P.stored(for: scale), phone: phone) == scale)
    }
}
for phone in [false, true] {
    check("Off 往返 \(phone)", P.textScale(stored: P.stored(for: nil), phone: phone) == nil)
}

// 文案非空。
check("标题", P.textSizeTitle == "Text Size")
check("脚注", P.textSizeFootnote.hasPrefix("A smaller size shows more") && P.textSizeFootnote.hasSuffix("in the toolbar."))

print("\(passes) 通过，\(fails) 失败")
exit(fails == 0 ? 0 : 1)
