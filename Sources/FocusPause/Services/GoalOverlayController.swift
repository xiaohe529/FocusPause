import AppKit
import SwiftUI

/// 原生窗口拖拽比在 SwiftUI `onChanged` 里逐帧 `setFrameOrigin` 更顺滑。
/// 右侧一小块保留给关闭按钮，其余区域直接交给系统拖拽会话。
private final class GoalOverlayPanel: NSPanel {
    private let closeButtonZone: CGFloat = 44
    /// 右键菜单里的「打开 FocusPause」。
    var onOpen: (() -> Void)?
    /// 右键菜单里的「关闭悬浮窗」。
    var onClose: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        // 右键（含 Control + 左键）弹菜单。左键一律只做拖动——
        // 「拖动」本身也是从一次鼠标按下开始的，靠位移去区分点击/拖动并不可靠，
        // 干脆不再把左键点击当作「打开主界面」。
        if event.type == .rightMouseDown {
            showContextMenu(at: event)
            return
        }

        guard event.type == .leftMouseDown,
              let contentView,
              contentView.frame.contains(event.locationInWindow) else {
            super.sendEvent(event)
            return
        }

        if event.modifierFlags.contains(.control) {
            showContextMenu(at: event)
            return
        }

        let closeButtonRect = NSRect(
            x: contentView.bounds.maxX - closeButtonZone,
            y: contentView.bounds.midY - closeButtonZone / 2,
            width: closeButtonZone,
            height: closeButtonZone
        )

        if closeButtonRect.contains(event.locationInWindow) {
            super.sendEvent(event)
            return
        }

        performDrag(with: event)   // 同步阻塞，直到系统拖拽会话结束
    }

    private func showContextMenu(at event: NSEvent) {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开 FocusPause", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        if onClose != nil {
            let close = NSMenuItem(title: "关闭悬浮窗", action: #selector(closeOverlay), keyEquivalent: "")
            close.target = self
            menu.addItem(close)
        }

        let point = contentView?.convert(event.locationInWindow, from: nil) ?? .zero
        menu.popUp(positioning: nil, at: point, in: contentView)
    }

    @objc private func openMainWindow() { onOpen?() }
    @objc private func closeOverlay() { onClose?() }
}

@MainActor
final class GoalOverlayController: NSWindowController {
    private var hostingController: NSHostingController<GoalOverlayView>?

    init() {
        let panel = GoalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // 全局置顶：跨所有空间、可显示在其它 App 之上；不能用 .stationary（会把它钉在当前空间）。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("GoalOverlayController cannot be created from a nib")
    }

    /// 悬浮目标窗：标题（专注计时中/延时屏蔽中）+ 可选事件文案 + 可选倒计时。
    /// `goal` 为 nil 时不显示事件；`end` 非 nil 时显示实时倒计时。
    func show(title: String, goal: String?, end: Date?, elapsedStart: Date? = nil, onClose: (() -> Void)? = nil) {
        FocusLogger.info("GoalOverlay show — title=\(title) window=\(window != nil)")
        let vc = NSHostingController(rootView: GoalOverlayView(
            title: title,
            goal: goal,
            end: end,
            elapsedStart: elapsedStart,
            onClose: onClose
        ))
        contentViewController = vc
        hostingController = vc

        let size = vc.view.fittingSize
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.minX + 24, y: frame.maxY - size.height - 24)
            window?.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        let panel = window as? GoalOverlayPanel
        panel?.onOpen = { [weak self] in
            self?.onOpenRequest?()
        }
        panel?.onClose = onClose
        window?.orderFrontRegardless()
    }

    /// 右键菜单里选「打开 FocusPause」时的回调，由 AppState 设为「呼起主窗口」。
    var onOpenRequest: (() -> Void)?

    func hide() {
        window?.orderOut(nil)
    }
}

struct GoalOverlayView: View {
    let title: String
    let goal: String?
    var end: Date?
    var elapsedStart: Date?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // 悬浮窗不设左侧色条：状态靠图标与文字，浮层本身已经从背景中分离出来。
            Image(systemName: title == "休息中" ? "cup.and.saucer.fill" : "target")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.focusAccent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.focusAccent)
                    if let end {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("剩余 \(countdownString(at: context.date, end: end))")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.focusInk)
                        }
                    } else if let elapsedStart {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("已 \(elapsedString(context.date, start: elapsedStart))")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.focusInk)
                        }
                    }
                }
                if let goal, !goal.isEmpty {
                    Text(goal)
                        .font(.headline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            if let onClose {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭悬浮目标")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FocusRadius.modal, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FocusRadius.modal, style: .continuous)
                .strokeBorder(Color.surfaceHairline, lineWidth: 1)
        )
    }

    private func countdownString(at now: Date, end: Date) -> String {
        guard end > now else { return "00:00" }
        let remaining = Int(end.timeIntervalSince(now))
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func elapsedString(_ now: Date, start: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
