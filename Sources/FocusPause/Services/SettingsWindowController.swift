import AppKit
import SwiftUI

/// Settings window controller — .regular policy with LSUIElement hides dock icon while keeping proper window activation.
class SettingsWindowController: NSWindowController {

    private var hostedView: Any?
    private weak var titlebarHost: NSView?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "FocusPause"
        // 参考 magpie 的窗口比例：略宽、偏横向，而不是正方形。
        window.minSize = NSSize(width: 680, height: 560)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FocusPauseSettings")
        // 参考 magpie：导航直接装进标题栏右侧（与红绿灯同一水平线），窗口内容不再被顶下去。
        window.titleVisibility = .hidden
        // 窗口跟随当前所在空间：打开时移到当前空间，避免被绑在旧的全屏 Space 上
        // （否则即使在桌面打开，系统也会切回之前那个全屏应用）。
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)

        window.delegate = self
    }

    func setContentView<V: View>(_ view: V) {
        let vc = NSHostingController(rootView: view.frame(minWidth: 680, minHeight: 560))
        contentViewController = vc
        hostedView = vc
        window?.minSize = NSSize(width: 680, height: 560)
    }

    /// 把一级导航装进标题栏右侧（magpie 的做法）。用标题栏 accessory 定位，
    /// 因此它天然与红绿灯对齐、高度一致，也不会把窗口内容往下推。
    /// 注意：accessory 视图宽度只跟随窗口 frame 变化，缩放窗口时需要手动同步，
    /// 否则导航会停在初始宽度上（靠右的应用名被挤掉或悬空）。
    func installTitlebarTabs(state: AppState) {
        guard let window else { return }
        let host = NSHostingView(rootView: TitlebarTabsView(state: state))
        titlebarHost = host
        host.frame = NSRect(x: 0, y: 0, width: window.frame.width, height: 46)
        host.autoresizingMask = [.width]
        host.translatesAutoresizingMaskIntoConstraints = true

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = host
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, let host = titlebarHost else { return }
        host.frame.size.width = window.frame.width
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        // Make sure accessory-app windows are raised even if another app is active.
        window?.orderFrontRegardless()
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
        // 自绘弹窗（和主界面同一套外观）；仍在后台运行，只是隐藏到菜单栏。
        var suppress = false
        NoticeDialogPresenter.run(NoticeDialogView(
            title: "将隐藏到菜单栏",
            icon: "pause.circle",
            message: "关闭窗口后 FocusPause 仍在后台运行，屏蔽和专注计时不受影响。",
            highlights: ["需要再次打开时，点击菜单栏顶部的暂停图标即可。"],
            checkboxTitle: "下次不再提醒",
            onCheckboxChange: { suppress = $0 },
            actions: [.init(title: "知道了", isPrimary: true) {}]
        ))
        if suppress {
            AppSettingsStore.standard.set(true, for: .minimizeHintSuppressed)
        }
        hide()
        return false
    }
}
