import AppKit
import Foundation

/// DMG 安装引导页背景（1320×800 px @144 DPI，即 660×400 pt 逻辑尺寸）。
///
/// 为什么要有这个脚本：背景是现画的一张图（文字 + 弧形箭头 + 留白），
/// 手改 PNG 没法跟着文案走，所以这里用代码合成，文案一改重跑即可。
/// 背景里**不放 logo**—— Finder 会画 `Focus&Pause.app` 自己的图标。
///
/// 布局必须和 `create-dmg` 的图标坐标对齐（Finder 用**左上角原点**）：
///   --window-size 660 400 --icon-size 128
///   --icon "Focus&Pause.app" 165 200  --app-drop-link 495 200
/// 即两个图标中心在 (165,200) 和 (495,200) —— 背景里那块位置要留空给 Finder 画。
///
/// 生成：
///   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift make-dmg-background.swift

private let pointW: CGFloat = 660
private let pointH: CGFloat = 400
private let scale: CGFloat = 2   // → 1320×800 px @144 DPI，Retina 清晰

private let ink = NSColor(red: 0.110, green: 0.110, blue: 0.130, alpha: 1)      // #1c1c21
private let secondary = NSColor(red: 0.42, green: 0.42, blue: 0.46, alpha: 1)
/// 强调色：与应用默认主题（暖赭）一致。
private let accent = NSColor(red: 0.706, green: 0.388, blue: 0.122, alpha: 1)
private let canvas = NSColor(red: 0.957, green: 0.957, blue: 0.965, alpha: 1)   // #f4f4f6

private func centerText(
    _ text: String,
    font: NSFont,
    color: NSColor,
    centerX: CGFloat,
    topY: CGFloat,
    tracking: CGFloat = 0
) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if tracking != 0 { attrs[.kern] = tracking }
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let size = attributed.size()
    // 传入的是「逻辑坐标里的顶部 y」，AppKit 绘制用底部原点，先换算成左上角原点再转回。
    let x = centerX - size.width / 2
    let y = pointH - topY - size.height
    attributed.draw(at: NSPoint(x: x, y: y))
    return size.height
}

private func systemFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func renderDMGBackground() -> NSBitmapImageRep {
    let pxW = Int(pointW * scale)
    let pxH = Int(pointH * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("cannot allocate bitmap") }
    // size 用逻辑尺寸 → 144 DPI，Finder 里按 660×400 铺满窗口。
    rep.size = NSSize(width: pointW, height: pointH)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState(); return rep
    }
    // 注意：不要手动 scaleBy —— rep.size 已声明为 660×400 逻辑尺寸，AppKit 会据此
    // 自动把逻辑坐标映射到 1320×800 像素；再 scale 一次会变成 4 倍、内容被裁掉。
    _ = ctx

    // ── 1. 底：与 App 页面底同一档浅灰 ───────────────────────────────
    canvas.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pointW, height: pointH)).fill()

    // 背景里不放 logo：那块位置留给 Finder 自己绘制的可拖拽 App 图标，
    // 背景再画一个会重复、也会让「拖哪个」变糊。

    // ── 2. 标题 ──────────────────────────────────────────────────────
    _ = centerText("Focus&Pause", font: systemFont(30, .semibold), color: ink,
                   centerX: pointW / 2, topY: 44, tracking: 0.2)
    _ = centerText("专注之外，也留一点休息的时间", font: systemFont(13, .regular), color: secondary,
                   centerX: pointW / 2, topY: 84)

    // ── 3. 手绘弧形箭头：落在两个图标槽之间、与图标同一中线 ──────────
    // 图标中心 y=200（左上角原点）→ 底部原点 y = 400-200 = 200
    let arrowY = pointH - 200
    let arrowStart: CGFloat = 165 + 128 / 2 + 30   // 左图标右缘再留一点
    let arrowEnd: CGFloat = 495 - 128 / 2 - 34     // 右图标左缘再留一点
    let span = arrowEnd - arrowStart

    // 笔身：一条微微上扬的弧线（用三次贝塞尔，避免死板的直线）。
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: arrowStart, y: arrowY - 8))
    shaft.curve(
        to: NSPoint(x: arrowEnd, y: arrowY + 2),
        controlPoint1: NSPoint(x: arrowStart + span * 0.34, y: arrowY + 12),
        controlPoint2: NSPoint(x: arrowStart + span * 0.70, y: arrowY + 12)
    )
    shaft.lineWidth = 3.4
    shaft.lineCapStyle = .round
    accent.setStroke()
    shaft.stroke()

    // 箭头头部：两笔手绘短线（不是实心三角），和笔身留一点小缺口。
    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowEnd - 15, y: arrowY + 12))
    head.line(to: NSPoint(x: arrowEnd, y: arrowY + 2))
    head.line(to: NSPoint(x: arrowEnd - 16, y: arrowY - 7))
    head.lineWidth = 3.4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    accent.setStroke()
    head.stroke()

    // 箭头下方的短提示
    _ = centerText("拖动安装", font: systemFont(13, .medium),
                   color: accent, centerX: pointW / 2, topY: 222)

    // ── 5. 底部提示 ──────────────────────────────────────────────────
    // 只留最要紧的一句。注意：Finder 会把背景图从标题栏下方开始铺，底部再被路径栏挡掉约 60pt，
    // 所以背景里 y≈340 以下其实看不见。这句必须落在图标名称（约 y≈298）之下、裁剪线之上。
    _ = centerText("升级前请先退出正在运行的 Focus&Pause",
                   font: systemFont(11, .regular), color: secondary,
                   centerX: pointW / 2, topY: 314)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep = renderDMGBackground()
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode PNG")
}
let out = "dmg-background.png"
try png.write(to: URL(fileURLWithPath: out))
print("Created \(out) (\(rep.pixelsWide)×\(rep.pixelsHigh) px @144 DPI)")
