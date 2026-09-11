import AppKit
import SwiftUI

/// Settings window controller — .regular policy with LSUIElement hides dock icon while keeping proper window activation.
class SettingsWindowController: NSWindowController {

    private var hostedView: Any?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Focus&Pause"
        window.minSize = NSSize(width: 640, height: 640)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FocusPauseSettings")
        // 窗口跟随当前所在空间：打开时移到当前空间，避免被绑在旧的全屏 Space 上
        // （否则即使在桌面打开，系统也会切回之前那个全屏应用）。
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)

        window.delegate = self
    }

    func setContentView<V: View>(_ view: V) {
        let vc = NSHostingController(rootView: view.frame(minWidth: 640, minHeight: 640))
        contentViewController = vc
        hostedView = vc
        window?.minSize = NSSize(width: 640, height: 640)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        // Don't auto-focus the first text field (e.g. the domain input on the website tab)
        // when the window opens. Defer to the next runloop so SwiftUI has laid out first.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SettingsWindowController: NSWindowDelegate {
    // ✕ hides the app to the menu bar instead of quitting. Show a one-time hint
    // as a sheet (attached to the app's own window), so the app isn't activated
    // and no Dock icon appears. Hide the window only after the sheet is dismissed.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !AppSettingsStore.standard.bool(.minimizeHintSuppressed) else {
            hide()
            return false
        }
        let alert = NSAlert()
        alert.messageText = "将隐藏到菜单栏"
        alert.informativeText = "关闭窗口后 FocusPause 仍在后台运行，屏蔽和专注计时不受影响。\n需要再次打开时，点击菜单栏顶部的锁形图标即可。"
        let checkbox = NSButton(checkboxWithTitle: "下次不再提醒", target: nil, action: nil)
        alert.accessoryView = checkbox
        alert.addButton(withTitle: "知道了")
        alert.beginSheetModal(for: sender) { [weak self] _ in
            if checkbox.state == .on {
                AppSettingsStore.standard.set(true, for: .minimizeHintSuppressed)
            }
            self?.hide()
        }
        return false
    }
}
