import AppKit
import SwiftUI

/// A small always-on-top panel that floats the current focus goal above other
/// apps during a delayed-block countdown. Non-activating and draggable so it
/// never steals focus from what the user is working on.
@MainActor
final class GoalOverlayController: NSWindowController {
    private var hostingController: NSHostingController<GoalOverlayView>?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
    func show(title: String, goal: String?, end: Date?, onClose: (() -> Void)? = nil) {
        FocusLogger.info("GoalOverlay show — title=\(title) window=\(window != nil)")
        let vc = NSHostingController(rootView: GoalOverlayView(title: title, goal: goal, end: end, onClose: onClose))
        contentViewController = vc
        hostingController = vc

        let size = vc.view.fittingSize
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.maxX - size.width - 24, y: frame.minY + 24)
            window?.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

struct GoalOverlayView: View {
    let title: String
    let goal: String?
    var end: Date?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.focusAccent)
                .frame(width: 4)
            Image(systemName: "target")
                .font(.system(size: 26, weight: .semibold))
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
                                .foregroundStyle(Color.focusDanger)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.focusAccent.opacity(0.6), lineWidth: 1.5)
        )
    }

    private func countdownString(at now: Date, end: Date) -> String {
        guard end > now else { return "00:00" }
        let remaining = Int(end.timeIntervalSince(now))
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}