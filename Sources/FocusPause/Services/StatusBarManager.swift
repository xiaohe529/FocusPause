import AppKit

/// Menu bar item — left-click to open settings, right-click for menu.
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
        // Enable both left and right click to trigger the action
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item

        // Auto-update icon when blocking state changes
        state.onBlockingStateChanged = { [weak self] in
            self?.updateIcon()
        }
    }

    @objc private func statusItemClicked() {
        // Check if it's a right-click
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let openItem = NSMenuItem(title: "打开设置", action: #selector(openSettings), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "退出", action: #selector(quitClicked), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            guard let button = statusItem?.button else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else {
            // Left-click — open settings directly
            settings?.show()
            updateIcon()
        }
    }

    @objc private func openSettings() {
        settings?.show()
        updateIcon()
    }

    @objc private func quitClicked() {
        state?.quitCleanup()
        NSApp.terminate(nil)
    }

    func updateIcon() {
        // 始终使用品牌暂停图标，不再回退到锁。实心 = 屏蔽中/处理中，空心 = 空闲。
        let name = (state?.blockingEnabled == true || state?.isProcessing == true)
            ? "pause.circle.fill"
            : "pause.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Focus&Pause")
        statusItem?.button?.image?.isTemplate = true
    }
}
