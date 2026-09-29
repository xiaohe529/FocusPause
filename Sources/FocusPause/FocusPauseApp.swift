import AppKit
import Carbon

/// 'lgni' — AppleEvent attribute value marking a launch as a login item.
private let kAELaunchedAsLogInItem: UInt32 = 0x6C676E69

class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsController: SettingsWindowController?
    private var statusBarManager: StatusBarManager?
    private var appNapActivity: NSObjectProtocol?

    /// True when the app was launched as a login item (SMAppService autostart),
    /// detected via the kAEOpenApplication launch event. Manual launches carry
    /// no login attribute, so they show the window.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let attr = event.attributeDescriptor(forKeyword: keyAEPropData) else {
            return false
        }
        return attr.typeCodeValue == kAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusLogger.info("FocusPause launching")
        // No dock icon
        NSApp.setActivationPolicy(.accessory)

        // Prevent App Nap so the focus timer and menu bar stay responsive even
        // when the app sits idle in the background for a long session. Otherwise
        // macOS throttles a hidden app and its timers/icon can lag or appear gone.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "FocusPause 屏蔽与专注计时保持运行"
        )

        installMainMenu()

        AppState.shared.load()

        // Settings window
        let settings = SettingsWindowController()
        settings.setContentView(MainView(state: AppState.shared))
        settingsController = settings

        // 弹窗里的「暂停一下/去呼吸」跳转：呼起主窗口并切到暂停页。
        AppState.shared.onOpenMainWindow = { [weak settings] in
            settings?.show()
        }

        // Menu bar item
        let statusBar = StatusBarManager()
        statusBar.setup(state: AppState.shared, settings: settings)
        statusBarManager = statusBar

        // Show the main window on a user-initiated launch (manual open), so users
        // aren't left wondering where the interface is. Login-item autostart stays
        // silent in the menu bar, reachable via the status bar icon.
        if !launchedAsLoginItem {
            settings.show()
        }

        // Auto-check for updates on launch (background, non-blocking).
        checkForUpdatesOnLaunch()
        FocusLogger.info("FocusPause launched — status bar ready")
    }

    /// Checks for a new version shortly after launch and, if one is available
    /// (and not ignored), prompts the user to download now or ignore this version.
    @MainActor
    private func checkForUpdatesOnLaunch() {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // let launch settle
            let status = await Updater.checkForUpdates()
            guard case .available(let version, let downloadURL, _) = status,
                  version != AppState.shared.ignoredUpdateVersion else { return }
            presentUpdateAlert(version: version, downloadURL: downloadURL)
        }
    }

    @MainActor
    private func presentUpdateAlert(version: String, downloadURL: URL?) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(version)"
        alert.informativeText = "当前版本 v\(Updater.currentVersion)，是否立即下载更新？"
        alert.addButton(withTitle: "立即下载")
        alert.addButton(withTitle: "忽略此版本")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            guard let downloadURL else { return }
            Task {
                if let err = await Updater.downloadAndOpen(downloadURL) {
                    let e = NSAlert()
                    e.messageText = "下载失败"
                    e.informativeText = err
                    e.addButton(withTitle: "知道了")
                    e.runModal()
                }
            }
        case .alertSecondButtonReturn:
            AppState.shared.ignoredUpdateVersion = version
        default:
            break // 稍后
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusLogger.info("FocusPause terminating")
        AppState.shared.quitCleanup()
    }

    /// Without a main menu, Cmd+C/Cmd+V/Cmd+A don't fire in SecureField/TextField
    /// (keyboard shortcuts are dispatched via menu items with key equivalents).
    /// LSUIElement/menu-bar apps ship without one by default — install a minimal
    /// Edit menu so paste works.
    @MainActor
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        appMenuItem.submenu = {
            let appMenu = NSMenu(title: "App")
            appMenu.addItem(withTitle: "关于 FocusPause", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            appMenu.addItem(NSMenuItem.separator())
            appMenu.addItem(withTitle: "退出 FocusPause", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return appMenu
        }()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editMenuItem.submenu = {
            let editMenu = NSMenu(title: "编辑")
            editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
            let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
            redoItem.keyEquivalentModifierMask = [.command, .shift]
            editMenu.addItem(redoItem)
            editMenu.addItem(NSMenuItem.separator())
            editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            return editMenu
        }()
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

@main
struct FocusPauseApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
