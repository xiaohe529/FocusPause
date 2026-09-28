import AppKit

/// Menu bar item — left-click opens settings, right-click shows quick actions.
@MainActor
class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private weak var state: AppState?
    private weak var settings: SettingsWindowController?

    func setup(state: AppState, settings: SettingsWindowController) {
        self.state = state
        self.settings = settings

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Focus&Pause")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // Enable both left and right click to trigger the action.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item

        // Auto-update icon when blocking state changes
        state.onBlockingStateChanged = { [weak self] in
            self?.updateIcon()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = makeContextMenu()
            guard let button = statusItem?.button else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else {
            settings?.show()
            updateIcon()
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let state = state

        let statusTitle: String
        switch (state?.isProcessing, state?.restActive, state?.focusTimerActive, state?.delayedBlockActive, state?.isScheduledLockActive, state?.blockingEnabled) {
        case (true, _, _, _, _, _):
            statusTitle = "正在处理…"
        case (_, true, _, _, _, _):
            statusTitle = "休息中"
        case (_, _, true, _, _, _):
            statusTitle = "专注计时中"
        case (_, _, _, true, _, _):
            statusTitle = "延时屏蔽中"
        case (_, _, _, _, true, _):
            statusTitle = "定时屏蔽中"
        case (_, _, _, _, _, true):
            statusTitle = "屏蔽中"
        default:
            statusTitle = "已停止"
        }

        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let toggleTitle = state?.blockingEnabled == true ? "停止屏蔽" : "开启屏蔽"
        let toggleItem = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleBlockingClicked),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.isEnabled = state?.isProcessing != true
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggleBlockingClicked() {
        state?.toggleBlocking()
        updateIcon()
    }

    @objc private func quitClicked() {
        state?.quitCleanup()
        NSApp.terminate(nil)
    }

    func updateIcon() {
        // 实心 = 屏蔽中/处理中，空心 = 空闲。
        let name = (state?.blockingEnabled == true || state?.isProcessing == true)
            ? "pause.circle.fill"
            : "pause.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Focus&Pause")
        statusItem?.button?.image?.isTemplate = true
    }
}
