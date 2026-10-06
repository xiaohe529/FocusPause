import AppKit
import Foundation

/// 应用图标：一只探头偷看的可爱黑猫（CatBar 风格）。
///
/// 设计约定（延续 App 的设计系统）：
/// - 圆角方块底 + 单一主体，无 Drop 阴影、无玻璃高光，保持 magpie 那种「素净」的观感。
/// - 构图在 16×16 也要认得出来：耳朵 + 大眼睛 + 底部横条是三个识别锚点。
///
/// 渲染注意：直接用 NSBitmapImageRep 按精确像素绘制。早期版本走 NSImage.lockFocus()，
/// 在 Retina 上会被放大成 2 倍，导致 iconset 里每张图都是标注尺寸的两倍。
private func u(_ v: CGFloat) -> CGFloat { v }

/// 圆角矩形路径。
private func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// 三角形（耳朵）。
private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: a); p.line(to: b); p.line(to: c); p.close()
    return p
}

private enum Palette {
    /// 底：近白中性（和 Magpie 图标同一套「素净的底」）。
    static let bg = NSColor(white: 0.98, alpha: 1)

    /// 猫身：墨色（沿用 App 的 focusInk），两档做出圆头体积感。
    static let fur = NSColor(red: 0.110, green: 0.110, blue: 0.130, alpha: 1)
    static let furShade = NSColor(red: 0.180, green: 0.180, blue: 0.208, alpha: 1)

    /// 唯二例外：眼睛用反白 + 一个极浅的灰点，让眼神有神（仍属单色系）。
    static let eye = NSColor(white: 0.99, alpha: 1)
    static let eyeShade = NSColor(white: 0.86, alpha: 1)
}

func renderIcon(px: CGFloat) -> NSBitmapImageRep {
    let dim = Int(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: dim, pixelsHigh: dim,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("cannot allocate bitmap") }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState(); return rep
    }

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: u(x) * px, y: u(y) * px) }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: u(x) * px, y: u(y) * px, width: u(w) * px, height: u(h) * px)
    }

    // ── 1. 圆角方块底 ────────────────────────────────────────────────
    let badge = R(0.08, 0.08, 0.84, 0.84)
    let badgePath = roundedRect(badge, radius: 0.84 * 0.224 * px)
    Palette.bg.setFill()
    badgePath.fill()

    // ── 2. 猫（先画身体与头，再让横条盖住下巴） ──────────────────────
    // 耳朵（在头后面）
    Palette.fur.setFill()
    triangle(P(0.250, 0.586), P(0.264, 0.828), P(0.472, 0.708)).fill()
    triangle(P(0.750, 0.586), P(0.736, 0.828), P(0.528, 0.708)).fill()

    // 耳朵内侧：留白（底色），单色更干净
    Palette.bg.setFill()
    triangle(P(0.300, 0.644), P(0.306, 0.744), P(0.412, 0.700)).fill()
    triangle(P(0.700, 0.644), P(0.694, 0.744), P(0.588, 0.700)).fill()

    // 头：宽而圆润的椭圆
    let head = R(0.190, 0.215, 0.620, 0.470)
    Palette.furShade.setFill()
    NSBezierPath(ovalIn: head).fill()
    // 额头主色（比外圈略深一档，塑造圆头体积感，不是玻璃高光）
    Palette.fur.setFill()
    NSBezierPath(ovalIn: R(0.210, 0.276, 0.580, 0.392)).fill()

    // ── 3. 眼睛：大而圆，琥珀金环 + 深瞳 + 高光 ──────────────────────
    func drawEye(cx: CGFloat, cy: CGFloat, r: CGFloat) {
        // 反白眼睛（底色挖出来），外圈一道细墨环——单色但眼神有神。
        Palette.eye.setFill()
        NSBezierPath(ovalIn: R(cx - r, cy - r, r * 2, r * 2)).fill()
        Palette.fur.setStroke()
        let ring = NSBezierPath(ovalIn: R(cx - r, cy - r, r * 2, r * 2))
        ring.lineWidth = max(1, px * 0.011)
        ring.stroke()
        // 瞳孔：一个小墨点
        Palette.fur.setFill()
        NSBezierPath(ovalIn: R(cx - r * 0.30, cy - r * 0.34, r * 0.60, r * 0.68)).fill()
        // 高光
        Palette.eyeShade.setFill()
        NSBezierPath(ovalIn: R(cx + r * 0.18, cy + r * 0.16, r * 0.44, r * 0.44)).fill()
    }
    drawEye(cx: 0.368, cy: 0.488, r: 0.0870)
    drawEye(cx: 0.632, cy: 0.488, r: 0.0870)

    // 鼻子（小墨三角）
    Palette.furShade.setFill()
    let nose = NSBezierPath()
    nose.move(to: P(0.472, 0.352)); nose.line(to: P(0.528, 0.352)); nose.line(to: P(0.500, 0.306))
    nose.close(); nose.fill()

    // ── 4. 横条：猫探在后面，只露出头和两只小爪 ────────────────────
    let ledgeRect = R(0.08, 0.08, 0.84, 0.170)
    let ledge = roundedRect(ledgeRect, radius: 0.055 * px)
    NSColor(white: 0.925, alpha: 1).setFill(); ledge.fill()
    // 横条顶部一道极细的高光边，制造「前沿」的层次
    NSColor(white: 0.855, alpha: 1).setStroke()
    ledge.lineWidth = max(1, px * 0.006)
    let topEdge = NSBezierPath()
    topEdge.move(to: CGPoint(x: ledgeRect.minX + 0.05 * px, y: ledgeRect.maxY))
    topEdge.line(to: CGPoint(x: ledgeRect.maxX - 0.05 * px, y: ledgeRect.maxY))
    topEdge.stroke()

    // 两只小爪搭在横条上
    Palette.fur.setFill()
    NSBezierPath(ovalIn: R(0.322, 0.212, 0.112, 0.092)).fill()
    NSBezierPath(ovalIn: R(0.566, 0.212, 0.112, 0.092)).fill()

    // 横条右侧的小装饰点（原参考里的两个小圆点）
    NSColor(white: 0.855, alpha: 1).setFill()
    NSBezierPath(ovalIn: R(0.740, 0.140, 0.028, 0.028)).fill()
    NSBezierPath(ovalIn: R(0.786, 0.140, 0.028, 0.028)).fill()

    // ── 5. 底板描边（与 App 卡片语言一致：一根 1px 细线） ────────────
    badgePath.lineWidth = max(1, px * 0.008)
    NSColor(red: 0, green: 0, blue: 0, alpha: 0.06).setStroke()
    badgePath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let iconset = "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    savePNG(renderIcon(px: px), to: "\(iconset)/\(name).png")
}

print("Created \(iconset)")
