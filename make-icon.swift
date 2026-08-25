import AppKit
import Foundation

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Badge: rounded rectangle inset 8% from each edge
    let inset = size * 0.08
    let badgeRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let badgeR = badgeRect.width * 0.224
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeR, yRadius: badgeR)

    // 靛蓝 → 青绿 对角渐变（呼应 focusAccent / focusActive）
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(red: 0.42, green: 0.47, blue: 0.72, alpha: 1.0).cgColor,
            NSColor(red: 0.30, green: 0.60, blue: 0.55, alpha: 1.0).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    badgePath.addClip()
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: [])
    ctx.restoreGState()

    // 顶部左上高光，增加一点立体感
    let hlInset = badgeRect.width * 0.015
    let hl = NSBezierPath(roundedRect: badgeRect.insetBy(dx: hlInset, dy: hlInset),
                           xRadius: badgeR * 0.88, yRadius: badgeR * 0.88)
    hl.lineWidth = size * 0.01
    NSColor.white.withAlphaComponent(0.18).setStroke()
    hl.stroke()

    // 暂停符号：两根圆角竖条
    let barW = badgeRect.width * 0.16
    let gap = badgeRect.width * 0.10
    let barH = badgeRect.width * 0.56
    let totalW = barW * 2 + gap
    let x0 = (size - totalW) / 2
    let y = (size - barH) / 2 + size * 0.01
    let barR = barW * 0.32

    let left = NSBezierPath(roundedRect: CGRect(x: x0, y: y, width: barW, height: barH),
                            xRadius: barR, yRadius: barR)
    let right = NSBezierPath(roundedRect: CGRect(x: x0 + barW + gap, y: y, width: barW, height: barH),
                             xRadius: barR, yRadius: barR)
    NSColor.white.withAlphaComponent(0.95).setFill()
    left.fill()
    right.fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
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
    let img = renderIcon(size: px)
    savePNG(img, to: "\(iconset)/\(name).png")
}

print("Created \(iconset)")
