import Foundation
import AppKit
import SwiftUI
import FocusPauseHelperShared
import ApplicationServices
import ServiceManagement
import CoreGraphics

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    let settings: AppSettingsStore

    init(settings: AppSettingsStore = .standard) {
        self.settings = settings
    }

    @Published var blockingEnabled = false
    @Published var blockRules: [BlockRule] = []
    @Published var hasPassword = false
    /// The version the user chose to ignore in the update prompt; nag again only
    /// when a newer version appears.
    var ignoredUpdateVersion: String? {
        get { settings.string(.ignoredUpdateVersion) }
        set { settings.set(newValue, for: .ignoredUpdateVersion) }
    }
    @Published var showPasswordSheet = false
    @Published var showEndElapsedConfirmation = false
    @Published var pendingToggleAction: (() -> Void)?
    @Published var pendingActionLabel: String = ""
    @Published var lastError: String?
    @Published var isProcessing = false
    @Published var launchAtLogin = false
    @Published var wifiDisabled = false
    @Published var focusTimerActive = false
    @Published var focusTimerEnd: Date? = nil
    /// 正计时（无结束时间、向上计时）的开始时刻；不为 nil 表示当前是正计时。
    @Published var focusTimerStart: Date? = nil
    /// 普通倒计时专注的开始时刻，用于绘制进度。
    @Published var focusCountdownStart: Date? = nil
    @Published var restActive = false
    @Published var restEnd: Date? = nil
    @Published var restGoal: String? = nil
    @Published var emergencyUsesThisMonth = 0
    @Published var showEmergencyOverrideSheet = false
    @Published var showEmergencyQuotaAlert = false
    @Published var emergencyQuotaAlertMessage = ""
    @Published var delayedBlockActive = false
    @Published var delayedBlockEnd: Date? = nil
    @Published var delayedBlockPendingAuth = false
    @Published var delayedBlockRetryCount = 0
    @Published var delayedBlockNextRetryAt: Date? = nil
    @Published var delayedBlockGoal: String? = nil
    @Published var focusTimerGoal: String? = nil
    @Published var delayedBlockLockScreen = false
    @Published var delayedBlockAllowExtension = true
    @Published var focusOverlayShowsTime = true
    @Published var helperInstalled = false
    @Published var helperNeedsRepair = false
    @Published var isInstallingHelper = false
    var helperInstallAttempted = false

    @Published var reminderEnabled = false
    @Published var reminderIntervalMinutes = 30
    @Published var showSettingsSheet = false
    @Published var coolingEnabled = false
    @Published var coolingMinutes = 5
    @Published var coolDownEndsAt: Date? = nil
    @Published var remindFocusTimerAfterBlock = true
    @Published var remindDelayedBlockAfterUnblock = true
    @Published var remindFocusTimerAfterEnd = false
    @Published var remindCountdownManualEnd = true
    @Published var remindRestManualEnd = true
    @Published var restLockScreen = false

    /// 强调色主题（设置里可切换）。变化时同步到 `Color.currentAccentTheme`。
    @Published var accentTheme: AccentTheme = .ochre {
        didSet { Color.currentAccentTheme = accentTheme }
    }

    /// 外观主题（跟随系统 / 浅色 / 深色），变化时立刻作用到整个 App。
    @Published var appearanceTheme: AppearanceTheme = .system {
        didSet { NSApp.appearance = appearanceTheme.nsAppearance }
    }
    @Published var showCooldownAlert = false
    @Published var remindBlockingNoFocus = false
    @Published var blockingNoFocusIntervalMinutes = 30

    // 定时屏蔽：多段时间段（每天重复 / 一次性）。
    @Published var scheduledWindows: [ScheduledWindow] = []
    /// 已「紧急退出」放弃的具体一次时间段（key=窗口id|yyyy-MM-dd）。紧急退出只解硬锁、屏蔽保持，
    /// 该标记让本次时间段不再重复加锁，直到下一次开始。
    @Published var releasedOccurrenceKey: String? = nil
    /// 定时屏蔽「紧急退出」每月已用次数（与专注计时的紧急退出额度相互独立）。
    @Published var scheduledExitUsesThisMonth = 0
    @Published var showScheduledExitSheet = false
    @Published var breakGlassEnabled = false
    @Published var breakGlassCooldownEnd: Date? = nil
    @Published var breakGlassLastAttemptDay: String? = nil
    /// 全拦总开关：开启后任何屏蔽状态都屏蔽全部网站 + App，忽略每条规则的开关。
    @Published var forceBlockAll = false

    // 正念：导航状态（弹窗可编程切页）+ 鼓励语
    enum PauseMode {
        case toolbox
        case grounding
        case cards
    }
    @Published var selectedTab = 0
    @Published var pauseMode: PauseMode = .toolbox
    @Published var prompts: [PromptItem] = []
    @Published var toolboxGroups: [ToolboxGroup] = []

    /// 弹窗跳转到练习页时，用来呼起主窗口。
    var onOpenMainWindow: (() -> Void)?

    private var reminderTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
    private var focusEndReminderTask: Task<Void, Never>?
    /// 专注计时结束的「稍后提醒」循环进行中时为 true，让「已屏蔽但未专注」循环让位，避免两个提醒同时弹。
    private var isFocusEndNagging = false
    /// 定时屏蔽的起止调度任务：start 前等待、到点开启。
    private var scheduledBlockTask: Task<Void, Never>?
    private var blockingNoFocusTask: Task<Void, Never>?
    /// 「稍后提醒」的一次性 nudge：无论对应提醒开关是否开启，都会在间隔后弹一次。
    private var reminderNudgeTask: Task<Void, Never>?
    private var blockingNoFocusNudgeTask: Task<Void, Never>?
    private var focusEndNudgeTask: Task<Void, Never>?
    private var focusTimerReminderNudgeTask: Task<Void, Never>?
    private var delayedBlockNudgeTask: Task<Void, Never>?
    /// 全局「正在弹提醒弹窗」闸：同一时刻只允许一个提醒弹窗（避免多个提醒同时触发时嵌套排队、背靠背）。
    private var reminderModalInFlight = false

    /// 尝试占用提醒弹窗闸；已有弹窗在弹则返回 false（调用方直接跳过，不排队）。
    private func beginReminderModal() -> Bool {
        guard !restActive else { return false }
        guard !reminderModalInFlight else { return false }
        reminderModalInFlight = true
        return true
    }
    private func endReminderModal() { reminderModalInFlight = false }

    /// 仅供测试：模拟「当前有提醒弹窗正在显示」。
    func setReminderModalInFlightForTesting(_ inFlight: Bool) {
        reminderModalInFlight = inFlight
    }

    /// Remaining cooldown after blocking was enabled; 0 when no cooldown is active.
    var coolDownRemaining: TimeInterval {
        guard let end = coolDownEndsAt else { return 0 }
        return max(0, end.timeIntervalSinceNow)
    }

    /// Callback for StatusBarManager to auto-update icon on state changes
    var onBlockingStateChanged: (() -> Void)?

    let appBlocker = AppBlocker()
    let wifiBlocker = WiFiBlocker()
    let focusTimerEngine = FocusTimerEngine()
    let restTimerEngine = FocusTimerEngine()
    private let goalOverlay = GoalOverlayController()

    /// 悬浮窗左键只做拖动；右键菜单里选「打开 FocusPause」才呼起主窗口。
    private func wireGoalOverlayActions() {
        goalOverlay.onOpenRequest = { [weak self] in
            self?.onOpenMainWindow?()
        }
    }
    private var goalOverlayDismissedByUser = false

    /// 专注计时「紧急退出」每月额度（用户可设 1–5，默认 3；每月仅可改一次）。
    @Published var restMinutes = 6
    @Published var emergencyQuota = 3
    /// 定时屏蔽「紧急退出」每月额度（与专注计时独立；用户可设 1–5，默认 3；每月仅可改一次）。
    @Published var scheduledExitQuota = 3
    /// 各额度最后一次修改的月份（yyyy-MM），用于「每月仅可改一次」。
    private var lastEmergencyQuotaSetMonth: String? = nil
    private var lastScheduledQuotaSetMonth: String? = nil

    var emergencyQuotaLockedThisMonth: Bool { lastEmergencyQuotaSetMonth == Self.currentMonthString() }
    var scheduledExitQuotaLockedThisMonth: Bool { lastScheduledQuotaSetMonth == Self.currentMonthString() }

    /// 设置专注计时紧急退出额度。本月已设过则拒绝并返回 false。
    @discardableResult
    func setEmergencyQuota(_ value: Int) -> Bool {
        let month = Self.currentMonthString()
        if lastEmergencyQuotaSetMonth == month {
            presentNotice("额度本月已锁定", "专注紧急退出额度本月已经设置过，下个月才能再改。")
            return false
        }
        emergencyQuota = min(5, max(1, value))
        lastEmergencyQuotaSetMonth = month
        settings.set(emergencyQuota, for: .emergencyQuota)
        settings.set(month, for: .emergencyQuotaSetMonth)
        FocusLogger.info("Emergency quota set to \(emergencyQuota) for \(month)")
        return true
    }

    /// 设置定时屏蔽紧急退出额度。本月已设过则拒绝并返回 false。
    @discardableResult
    func setScheduledExitQuota(_ value: Int) -> Bool {
        let month = Self.currentMonthString()
        if lastScheduledQuotaSetMonth == month {
            presentNotice("额度本月已锁定", "定时屏蔽紧急退出额度本月已经设置过，下个月才能再改。")
            return false
        }
        scheduledExitQuota = min(5, max(1, value))
        lastScheduledQuotaSetMonth = month
        settings.set(scheduledExitQuota, for: .scheduledExitQuota)
        settings.set(month, for: .scheduledExitQuotaSetMonth)
        FocusLogger.info("Scheduled-exit quota set to \(scheduledExitQuota) for \(month)")
        return true
    }

    private var lastResetMonth: String = ""

    var isLocked: Bool { focusTimerActive || restActive }

    /// 弹一个提示框。用于「用户点了某个按钮、但当前状态不允许」这类拒绝，
    /// 比底部条幅更容易被看到（条幅会被忽略，用户以为点了没反应）。
    /// 用自绘面板直接弹，不走主窗口的 sheet：这些提示经常由菜单栏或
    /// 屏蔽中的列表操作触发，走 sheet 就得先把主窗口叫出来，
    /// 用户会看到「主界面自己冒出来」。面板自己居中，处理完就还原现场。
    /// 表单内的校验错误（如域名格式、密码错误）仍然走 `lastError` 就近显示。
    ///
    /// 必须推迟一个 runloop turn：调用点几乎都在 SwiftUI `Button` 的 action 里，
    /// 手势栈尚未退出时直接 `NSApp.runModal` 会开启嵌套事件循环接管 runloop，
    /// 弹窗里的点击永远送不到按钮上——表现为「弹窗出现了但点了没反应」，
    /// 主线程 100% 卡在 `runModal` 里，整个 App 看起来是卡死的。
    func presentNotice(_ title: String, _ message: String) {
        DialogPanelFactory.runDeferred {
            NoticeDialogPresenter.run(NoticeDialogView(
                title: title,
                icon: "exclamationmark.triangle",
                message: message,
                actions: [.init(title: "知道了", isPrimary: true) {}]
            ))
        }
    }

    /// 屏蔽名单处于锁定状态（休息 / 专注计时 / 屏蔽开启中）时返回提示文案，否则 nil。
    func ruleListLockedError() -> String? {
        if restActive { return "休息中，屏蔽名单已锁定，无法删除条目" }
        if focusTimerActive { return "专注计时中，屏蔽名单已锁定，无法删除条目" }
        if blockingEnabled { return "屏蔽开启中，屏蔽名单已锁定，无法删除条目" }
        return nil
    }

    /// 名单锁定时用弹窗打断：条幅容易被忽略，删除/关闭这类操作需要用户明确看到被拒绝的原因。
    func presentRuleListLockedNotice() {
        presentNotice(
            "屏蔽名单已锁定",
            (ruleListLockedError() ?? "当前状态下无法修改屏蔽名单")
                + "。名单只能增加，不能减少；需要改动请先停止屏蔽或结束计时。"
        )
    }

    // MARK: - 定时屏蔽（多段时间段：每天重复 / 一次性）

    /// 用户已提前退出的那一次时间段标记（key=窗口id|同日起止日）。返回 nil 代表当前不在任何时段。
    func activeOccurrenceKey(now: Date = Date()) -> String? {
        activeMatch(now: now)?.key
    }

    /// 当前正处在屏蔽时间段内的那条窗口（用于锁定该窗口不被编辑）。
    var activeScheduledWindowID: UUID? {
        activeMatch()?.window.id
    }

    private func activeMatch(now: Date = Date()) -> (window: ScheduledWindow, key: String)? {
        let calendar = Calendar.current
        for window in scheduledWindows where window.enabled {
            if let key = window.activeKey(now: now, calendar: calendar) {
                return (window, key)
            }
        }
        return nil
    }

    /// 是否处于定时屏蔽硬锁内：当前在某段时间段，且该次时间段未被紧急退出放弃。
    var isScheduledLockActive: Bool {
        guard let key = activeOccurrenceKey() else { return false }
        return key != releasedOccurrenceKey
    }

    var activeTimerKind: FocusTimerState.Kind? {
        if focusTimerActive { return .focus }
        if delayedBlockActive { return .delayedBlock }
        if isScheduledLockActive { return .scheduledBlock }
        return nil
    }

    /// 是否处于「正计时」（无结束时间、向上计时）。
    var isElapsedFocus: Bool { focusTimerStart != nil && focusTimerEnd == nil }

    /// The goal for whichever session is currently active (focus timer or
    /// delayed block), shown in the floating always-on-top overlay.
    private var activeGoal: String? {
        if restActive { return restGoal }
        if focusTimerActive { return focusTimerGoal }
        if delayedBlockActive { return delayedBlockGoal }
        return nil
    }

    // MARK: - 有效屏蔽规则（受全拦总开关影响）

    /// 实际用于屏蔽的网站域名：全拦开启时忽略每条规则开关。
    var invalidWebsiteRules: [BlockRule] {
        blockRules.filter { $0.type == .website && DomainNormalizer.normalize($0.name) == nil }
    }

    var effectiveWebsites: [String] {
        blockRules
            .filter { $0.type == .website && (forceBlockAll || $0.enabled) }
            .compactMap { DomainNormalizer.normalize($0.name) }
    }
    /// 实际用于屏蔽的 App 名称：同上。
    var effectiveApps: [String] {
        blockRules.filter { $0.type == .app && (forceBlockAll || $0.enabled) }.map { $0.name }
    }

    private var settingsURL: URL {
        HostsBlocker.backupDir().appendingPathComponent("settings.json")
    }

    private var focusTimerURL: URL {
        HostsBlocker.backupDir().appendingPathComponent("focustimer.json")
    }

    func load() {
        wireGoalOverlayActions()
        FocusLogger.info("AppState load begin")

        migrateLegacyDefaultsIfNeeded()

        if let data = try? Data(contentsOf: settingsURL),
           let saved = try? JSONDecoder().decode(SettingsStorage.self, from: data) {
            blockRules = saved.blockRules
            FocusLogger.info("Loaded \(blockRules.count) block rules from settings.json")
        } else {
            FocusLogger.info("No settings.json or decode failed — starting fresh")
        }

        hasPassword = KeychainPassword.load() != nil

        launchAtLogin = settings.bool(.launchAtLogin)
        if let enabled = settings.object(.blockingEnabled) as? Bool {
            blockingEnabled = enabled
        }
        forceBlockAll = settings.bool(.forceBlockAll)
        loadScheduledWindows()
        if let q = settings.optionalInt(.emergencyQuota) {
            emergencyQuota = min(5, max(1, q))
        }
        if let q = settings.optionalInt(.scheduledExitQuota) {
            scheduledExitQuota = min(5, max(1, q))
        }
        lastEmergencyQuotaSetMonth = settings.string(.emergencyQuotaSetMonth)
        lastScheduledQuotaSetMonth = settings.string(.scheduledExitQuotaSetMonth)
        delayedBlockLockScreen = settings.bool(.delayedBlockLockScreen)
        delayedBlockAllowExtension = settings.bool(.delayedBlockAllowExtension, default: true)
        focusOverlayShowsTime = settings.bool(.focusOverlayShowsTime, default: true)

        appBlocker.updateBlockedApps(effectiveApps)
        appBlocker.setBlockingEnabled(blockingEnabled)

        appBlocker.start()
        // Check WiFi status without triggering admin prompt — deferred to avoid startup interference
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            wifiBlocker.checkStatusQuiet()
        }

        // Probe privileged helper — then restore blocking only if helper is already installed.
        // Otherwise skip restore so first open doesn't trigger an admin password prompt.
        // User clicks "开启屏蔽" to install helper and resume blocking.
        Task { @MainActor in
            let helperRunning = await HelperInstaller.isRunning()
            self.helperInstalled = helperRunning
            self.helperNeedsRepair = helperRunning && !HelperInstaller.tokenPermissionsAreSecure()
            guard helperRunning else {
                FocusLogger.info("Helper not running — keeping persisted blocking state")
                if self.blockingEnabled {
                    self.lastError = "后台助手未运行，当前屏蔽保持，但更新规则前需要重新安装助手。"
                }
                return
            }
            if self.helperNeedsRepair {
                self.lastError = "后台助手需要安全修复，请重新安装助手。"
                return
            }
            guard self.blockingEnabled else { return }
            let domains = self.effectiveWebsites
            if !domains.isEmpty {
                FocusLogger.info("Restoring website blocking for \(domains.count) domains")
                Task {
                    do {
                        try await HostsBlocker.apply(domains: domains)
                        self.lastError = nil
                    } catch {
                        FocusLogger.error("Restore blocking failed: \(error.localizedDescription)")
                        self.lastError = "恢复屏蔽失败：\(error.localizedDescription)"
                        self.blockingEnabled = false
                        self.appBlocker.setBlockingEnabled(false)
                    }
                }
            }
        }

        loadFocusTimer()

        reminderEnabled = settings.bool(.reminderEnabled)
        let storedInterval = settings.optionalInt(.reminderIntervalMinutes)
        reminderIntervalMinutes = storedInterval ?? 30
        if reminderIntervalMinutes < 1 { reminderIntervalMinutes = 1 }
        startReminderLoop()

        remindBlockingNoFocus = settings.bool(.remindBlockingNoFocus)
        let storedBNF = settings.optionalInt(.blockingNoFocusIntervalMinutes)
        blockingNoFocusIntervalMinutes = storedBNF ?? 30
        if blockingNoFocusIntervalMinutes < 1 { blockingNoFocusIntervalMinutes = 1 }
        startBlockingNoFocusLoop()

        coolingEnabled = settings.bool(.coolingEnabled)
        let storedCooling = settings.optionalInt(.coolingMinutes)
        coolingMinutes = storedCooling ?? 5
        if coolingMinutes < 1 { coolingMinutes = 1 }
        remindFocusTimerAfterBlock = settings.bool(.remindFocusTimerAfterBlock, default: true)
        remindDelayedBlockAfterUnblock = settings.bool(.remindDelayedBlockAfterUnblock, default: true)
        remindFocusTimerAfterEnd = settings.bool(.remindFocusTimerAfterEnd, default: false)
        remindCountdownManualEnd = settings.bool(.remindCountdownManualEnd, default: true)
        remindRestManualEnd = settings.bool(.remindRestManualEnd, default: true)
        restLockScreen = settings.bool(.restLockScreen)
        if let raw = settings.string(.accentTheme), let theme = AccentTheme(rawValue: raw) {
            accentTheme = theme
        }
        Color.currentAccentTheme = accentTheme
        if let raw = settings.string(.appearanceTheme), let theme = AppearanceTheme(rawValue: raw) {
            appearanceTheme = theme
        }
        NSApp.appearance = appearanceTheme.nsAppearance
        breakGlassEnabled = settings.bool(.breakGlassEnabled)

        loadPrompts()
        loadToolboxLinks()

        FocusLogger.info("AppState load complete — blockingEnabled=\(blockingEnabled) hasPassword=\(hasPassword)")
    }

    /// 一次性迁移：开发阶段曾用「裸二进制」运行（UserDefaults 域 = 进程名 FocusPause），
    /// 而打包 .app 的域是 com.focuspause.app，两边配置可能各存一份。
    /// 首次以 .app 运行时，把旧域的键复制进当前域（当前域已有的键不覆盖）。
    private func migrateLegacyDefaultsIfNeeded() {
        guard !settings.bool(.didMigrateLegacyDefaults) else { return }
        settings.set(true, for: .didMigrateLegacyDefaults)
        guard let legacy = UserDefaults(suiteName: "FocusPause") else { return }
        let keys: [AppSettingsStore.Key] = [
            .prompts, .toolboxLinks, .toolboxGroups,
            .reminderEnabled, .reminderIntervalMinutes,
            .coolingEnabled, .coolingMinutes,
            .remindFocusTimerAfterBlock, .remindDelayedBlockAfterUnblock, .remindFocusTimerAfterEnd,
            .remindCountdownManualEnd, .remindRestManualEnd,
            .remindBlockingNoFocus, .blockingNoFocusIntervalMinutes,
            .launchAtLogin, .blockingEnabled,
            .delayedBlockLockScreen, .delayedBlockAllowExtension,
            .focusOverlayShowsTime, .breakGlassEnabled,
            .ignoredUpdateVersion,
        ]
        var migrated = false
        for key in keys {
            guard settings.object(key) == nil,
                  let value = legacy.object(forKey: key.rawValue) else { continue }
            settings.set(value, for: key)
            migrated = true
        }
        if migrated {
            FocusLogger.info("Migrated legacy UserDefaults from 'FocusPause' domain")
        }
    }

    private func loadFocusTimer() {
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in
                self?.focusTimerExpired()
            }
        }

        let currentMonth = Self.currentMonthString()
        var loaded = FocusTimerState(endTimestamp: nil,
                                     emergencyUsesThisMonth: 0,
                                     lastResetMonth: currentMonth)

        if let data = try? Data(contentsOf: focusTimerURL),
           let saved = try? JSONDecoder().decode(FocusTimerState.self, from: data) {
            loaded = saved
        }

        // Monthly reset
        if loaded.lastResetMonth != currentMonth {
            FocusLogger.info("Month changed \(loaded.lastResetMonth) → \(currentMonth), resetting emergency & scheduled-exit quota")
            loaded.emergencyUsesThisMonth = 0
            loaded.scheduledExitUsesThisMonth = 0
            loaded.lastResetMonth = currentMonth
        }
        emergencyUsesThisMonth = loaded.emergencyUsesThisMonth
        scheduledExitUsesThisMonth = loaded.scheduledExitUsesThisMonth ?? 0
        lastResetMonth = loaded.lastResetMonth
        breakGlassCooldownEnd = loaded.breakGlassCooldownEnd
        breakGlassLastAttemptDay = loaded.breakGlassLastAttemptDay

        // Restore an active rest timer; it must survive app restarts.
        if loaded.restActive == true, let restEnd = loaded.restEnd, restEnd <= Date() {
            loaded.restActive = false
            loaded.restEnd = nil
            loaded.restGoal = nil
            FocusLogger.info("Discarded expired persisted rest timer")
        }

        // Reset transient timer state — will be repopulated below
        focusTimerActive = false
        focusTimerEnd = nil
        focusTimerStart = nil
        focusCountdownStart = nil
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockPendingAuth = false
        delayedBlockRetryCount = 0
        delayedBlockNextRetryAt = nil
        delayedBlockGoal = loaded.delayedBlockGoal
        focusTimerGoal = loaded.focusTimerGoal

        // Resume active rest timer before other timers.
        if loaded.restActive == true, let end = loaded.restEnd, end > Date() {
            restActive = true
            restEnd = end
            restGoal = loaded.restGoal
            restMinutes = loaded.restMinutes ?? 6
            goalOverlayDismissedByUser = false
            restTimerEngine.onExpire = { [weak self] in
                Task { @MainActor in self?.restExpired() }
            }
            restTimerEngine.start(endTimestamp: end)
            refreshGoalOverlay()
            FocusLogger.info("Resumed active rest timer, ends at \(end)")
            return
        }

        // Resume active 正计时（无结束时间、向上计时）
        if (loaded.kind ?? .focus) == .focus, loaded.endTimestamp == nil, let start = loaded.focusTimerStart {
            focusTimerStart = start
            focusTimerActive = true
            focusTimerGoal = loaded.focusTimerGoal
            goalOverlayDismissedByUser = false
            focusTimerEngine.stop()
            refreshGoalOverlay()
            FocusLogger.info("Resumed elapsed focus timer, started at \(start)")
        } else if let end = loaded.endTimestamp, end > Date() {
            // Resume active (倒计时) timer if end is still in the future
            let kind = loaded.kind ?? .focus
            switch kind {
            case .focus:
                focusTimerEnd = end
                focusTimerActive = true
                focusCountdownStart = loaded.focusCountdownStart
                focusTimerEngine.onExpire = { [weak self] in
                    Task { @MainActor in self?.focusTimerExpired() }
                }
                FocusLogger.info("Resumed active focus timer, ends at \(end)")
            case .delayedBlock:
                delayedBlockEnd = end
                delayedBlockActive = true
                delayedBlockRetryCount = loaded.delayedBlockRetryCount ?? 0
                focusTimerEngine.onExpire = { [weak self] in
                    Task { @MainActor in self?.delayedBlockExpired() }
                }
                FocusLogger.info("Resumed active delayed-block timer, ends at \(end)")
            case .scheduledBlock:
                // 定时屏蔽窗口由 scheduledBlockStart/End 单独恢复并调度（见 load 上文），
                // 不占用这里的 endTimestamp。
                FocusLogger.info("Scheduled-block kind persisted (no endTimestamp) — resumed via scheduledBlockStart/End")
                break
            }
            focusTimerEngine.start(endTimestamp: end)
            refreshGoalOverlay()
        } else if loaded.delayedBlockPendingAuth == true {
            // Timer expired but blocking failed (user cancelled admin prompt) — restore pending state
            delayedBlockPendingAuth = true
            delayedBlockRetryCount = loaded.delayedBlockRetryCount ?? 0
            FocusLogger.info("Resumed pending-auth state, retryCount=\(delayedBlockRetryCount)")
            // Do not run a modal panel while applicationDidFinishLaunching is still active.
            // Otherwise the main window can take focus and the panel can be left hidden/tiny.
            scheduleStartupPendingAlert()
        } else {
            saveFocusTimer()
        }
    }

    private static func currentMonthString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    func startFocusTimer(minutes: Int, goal: String? = nil) {
        guard !restActive else {
            presentNotice("休息中", "请先结束休息，再开始专注。")
            return
        }
        guard !delayedBlockActive else {
            presentNotice("延时屏蔽进行中", "延时屏蔽倒计时结束、正式开启屏蔽后才能启动专注计时。")
            return
        }
        guard blockingEnabled else {
            presentNotice("需要先开启屏蔽", "专注计时会锁定屏蔽设置，所以要先开启屏蔽。")
            return
        }
        guard focusTimerStart == nil else { return }   // 正计时进行中，不叠计
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        cancelAllNudges()
        stopFocusEndReminder()
        focusTimerEnd = end
        focusTimerActive = true
        focusCountdownStart = Date()
        focusTimerGoal = goal?.isEmpty == true ? nil : goal
        goalOverlayDismissedByUser = false
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.focusTimerExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Started focus timer: \(minutes) min, ends at \(end)")
    }

    /// 开始「正计时」：无结束时间、向上计时。结束需密码且不消耗紧急退出额度。
    func startFocusTimerElapsed(goal: String? = nil) {
        guard !restActive else {
            presentNotice("休息中", "请先结束休息，再开始专注。")
            return
        }
        guard !delayedBlockActive else {
            presentNotice("延时屏蔽进行中", "延时屏蔽倒计时结束、正式开启屏蔽后才能启动专注计时。")
            return
        }
        guard blockingEnabled else {
            presentNotice("需要先开启屏蔽", "专注计时会锁定屏蔽设置，所以要先开启屏蔽。")
            return
        }
        guard !focusTimerActive else {
            presentNotice("已有专注计时", "当前已有专注计时在运行，先结束它再开始新的。")
            return
        }
        cancelAllNudges()
        stopFocusEndReminder()
        focusTimerEnd = nil
        focusTimerStart = Date()
        focusTimerActive = true
        focusTimerGoal = goal?.isEmpty == true ? nil : goal
        goalOverlayDismissedByUser = false
        focusTimerEngine.stop()   // 无到期，不启用引擎
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Started elapsed focus timer")
    }

    /// 请求结束正计时：只需普通确认，不消耗紧急退出额度。
    func requestEndElapsedFocus() {
        guard isElapsedFocus else { return }
        showEndElapsedConfirmation = true
    }

    /// 结束「正计时」（已通过确认弹窗）：只清计时、不扣紧急退出额度。
    func endFocusTimerElapsed() {
        guard isElapsedFocus else { return }
        focusTimerActive = false
        focusTimerStart = nil
        focusTimerEnd = nil
        focusTimerGoal = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Ended elapsed focus timer (no quota used)")
        if remindFocusTimerAfterEnd {
            startFocusEndReminderLoop()
        }
    }

    func focusTimerExpired() {
        FocusLogger.info("Focus timer expired naturally")
        focusTimerActive = false
        focusTimerEnd = nil
        focusCountdownStart = nil
        focusTimerGoal = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
        startFocusEndReminderLoop()
    }

    /// Opens the password sheet only if quota remains; otherwise explains the state.
    func requestEmergencyOverride() {
        guard emergencyUsesThisMonth < emergencyQuota else {
            emergencyQuotaAlertMessage = "本月专注紧急退出次数已用完。请等待计时自然结束；如确属紧急，可先检查应急解锁是否可用。"
            showEmergencyQuotaAlert = true
            return
        }
        showEmergencyOverrideSheet = true
    }

    /// Opens the password sheet only if quota remains; otherwise explains the state.
    func requestScheduledExit() {
        guard scheduledExitUsesThisMonth < scheduledExitQuota else {
            emergencyQuotaAlertMessage = "本月定时屏蔽紧急退出次数已用完。请等待时间段结束；如确属紧急，可先检查应急解锁是否可用。"
            showEmergencyQuotaAlert = true
            return
        }
        showScheduledExitSheet = true
    }

    /// Returns true on success (timer cleared). Returns false on wrong password
    /// or quota exhausted, setting lastError.
    func emergencyOverride(password: String) -> Bool {
        guard KeychainPassword.verify(password) else {
            FocusLogger.error("Emergency override failed: wrong password")
            lastError = "密码错误"
            return false
        }
        guard emergencyUsesThisMonth < emergencyQuota else {
            FocusLogger.error("Emergency override failed: quota exhausted (\(emergencyUsesThisMonth)/\(emergencyQuota))")
            lastError = "本月紧急退出次数已用完"
            return false
        }
        emergencyUsesThisMonth += 1
        // 专注计时：清掉计时（屏蔽本身仍保持）。
        if focusTimerActive {
            focusTimerActive = false
            focusTimerEnd = nil
            focusCountdownStart = nil
            focusTimerGoal = nil
            focusTimerEngine.stop()
            if remindCountdownManualEnd {
                DispatchQueue.main.async { [weak self] in
                    self?.presentFocusEndReminder()
                }
            }
        }
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Emergency override succeeded, uses this month: \(emergencyUsesThisMonth)")
        return true
    }

    /// 定时屏蔽「紧急退出」（密码已在 sheet 验证）：与专注计时额度和互独立。
    /// 消耗本套月度额度，只解除本次时间段硬锁，屏蔽保持开启。
    func scheduledBlockEmergencyExit(password: String) -> Bool {
        guard KeychainPassword.verify(password) else {
            lastError = "密码错误"
            return false
        }
        guard isScheduledLockActive else {
            lastError = "当前不在定时屏蔽时间段内"
            return false
        }
        guard scheduledExitUsesThisMonth < scheduledExitQuota else {
            presentNotice("次数已用完", "本月定时屏蔽紧急退出次数已用完，请等到时间段结束。")
            FocusLogger.error("Scheduled exit rejected: quota exhausted (\(scheduledExitUsesThisMonth)/\(scheduledExitQuota))")
            return false
        }
        scheduledExitUsesThisMonth += 1
        releaseScheduledLockViaEmergencyExit()
        saveFocusTimer()   // 持久化月度额度
        FocusLogger.info("Scheduled emergency exit used \(scheduledExitUsesThisMonth)/\(scheduledExitQuota)")
        return true
    }


    // MARK: - Break-glass emergency unlock

    static let breakGlassConfirmationPhrase = "我确认这是真实的紧急情况"
    static let breakGlassCooldownSeconds: TimeInterval = 5 * 60

    private static func currentDayString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var breakGlassHardLockQuotaExhausted: Bool {
        if focusTimerActive {
            return emergencyUsesThisMonth >= emergencyQuota
        }
        if isScheduledLockActive {
            return scheduledExitUsesThisMonth >= scheduledExitQuota
        }
        return false
    }

    var canConfigureBreakGlass: Bool {
        !blockingEnabled &&
        !focusTimerActive &&
        !restActive &&
        !delayedBlockActive &&
        !delayedBlockPendingAuth &&
        !isScheduledLockActive &&
        breakGlassCooldownEnd == nil
    }

    /// 额度用完的硬锁中也允许从设置启用，否则会产生无法救援的死角。
    var canEnableBreakGlassDuringLock: Bool {
        !breakGlassEnabled &&
        breakGlassHardLockQuotaExhausted &&
        breakGlassCooldownEnd == nil &&
        breakGlassLastAttemptDay != Self.currentDayString()
    }

    /// Closing the feature is safe: it does not change any active lock.
    var canCloseBreakGlass: Bool {
        breakGlassEnabled && breakGlassCooldownEnd == nil
    }

    func canStartBreakGlassUnlock(at date: Date = Date()) -> Bool {
        breakGlassEnabled &&
        breakGlassHardLockQuotaExhausted &&
        breakGlassCooldownEnd == nil &&
        breakGlassLastAttemptDay != Self.currentDayString(for: date)
    }

    func isBreakGlassInCooldown(at date: Date = Date()) -> Bool {
        guard let end = breakGlassCooldownEnd else { return false }
        return date < end
    }

    func isBreakGlassReadyToComplete(at date: Date = Date()) -> Bool {
        guard let end = breakGlassCooldownEnd else { return false }
        return date >= end
    }

    func setBreakGlassEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard canConfigureBreakGlass || canEnableBreakGlassDuringLock else {
                lastError = "应急解锁当前不可启用"
                return false
            }
        } else {
            guard canConfigureBreakGlass || canCloseBreakGlass else {
                lastError = "冷静期内请先放弃解锁，再关闭应急解锁"
                return false
            }
        }

        breakGlassEnabled = enabled
        settings.set(enabled, for: .breakGlassEnabled)
        FocusLogger.info("Break-glass unlocked setting changed: \(enabled)")
        return true
    }

    @discardableResult
    func startBreakGlassUnlock(password: String, confirmationPhrase: String) -> Bool {
        guard canStartBreakGlassUnlock() else {
            lastError = "应急解锁当前不可用"
            return false
        }
        guard helperInstalled, !helperNeedsRepair else {
            lastError = "后台助手不可用，请先修复后再试"
            return false
        }
        guard confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == Self.breakGlassConfirmationPhrase else {
            lastError = "确认语句不一致"
            return false
        }
        guard KeychainPassword.verify(password) else {
            lastError = "密码错误"
            return false
        }

        let today = Self.currentDayString()
        breakGlassCooldownEnd = Date().addingTimeInterval(Self.breakGlassCooldownSeconds)
        breakGlassLastAttemptDay = today
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Break-glass cooldown started, ends at \(breakGlassCooldownEnd!)")
        return true
    }

    /// Keeps all blocking rules active and only abandons the pending unlock.
    @discardableResult
    func cancelBreakGlassUnlock() -> Bool {
        guard isBreakGlassInCooldown() else {
            lastError = "当前没有进行中的应急解锁"
            return false
        }

        breakGlassCooldownEnd = nil
        saveFocusTimer()
        FocusLogger.info("Break-glass unlock abandoned; blocking remains active")
        return true
    }

    func completeBreakGlassUnlock() async {
        guard isBreakGlassReadyToComplete() else {
            lastError = "应急解锁冷静期未结束"
            return
        }

        FocusLogger.info("Break-glass unlock completing")
        isProcessing = true
        onBlockingStateChanged?()

        // Keep local locks intact until the privileged helper confirms hosts cleanup.
        let releasedOccurrenceKey = activeOccurrenceKey()
        do {
            try await HostsBlocker.clear()
        } catch {
            FocusLogger.error("Break-glass unlock failed: \(error.localizedDescription)")
            lastError = "应急解锁失败：\(error.localizedDescription)"
            isProcessing = false
            onBlockingStateChanged?()
            return
        }

        // System-level rules are gone; now stop every in-app timer/lock.
        restTimerEngine.stop()
        focusTimerEngine.stop()
        scheduledBlockTask?.cancel()
        pendingAlertTask?.cancel()

        restActive = false
        restEnd = nil
        restGoal = nil
        focusTimerActive = false
        focusTimerEnd = nil
        focusTimerStart = nil
        focusCountdownStart = nil
        focusTimerGoal = nil
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockPendingAuth = false
        delayedBlockRetryCount = 0
        delayedBlockNextRetryAt = nil
        delayedBlockGoal = nil
        goalOverlayDismissedByUser = false

        if let key = releasedOccurrenceKey {
            setReleasedOccurrence(key)
        }
        blockingEnabled = false
        appBlocker.setBlockingEnabled(false)
        lastError = nil

        appBlocker.stop()
        cooldownTask?.cancel()
        coolDownEndsAt = nil
        stopFocusEndReminder()
        stopBlockingNoFocusLoop()
        stopPendingAlertLoop()
        cancelAllNudges()
        breakGlassCooldownEnd = nil
        refreshGoalOverlay()
        _ = await save()
        saveFocusTimer()
        isProcessing = false
        onBlockingStateChanged?()
        FocusLogger.info("Break-glass unlock completed")
    }

    /// 持久化用的 (kind, endTimestamp)。两者必须成对取自同一个来源：
    /// `.scheduledBlock` 由 scheduledWindows 独立恢复，不占用 endTimestamp，
    /// 写作 nil 以免写出一个「有 kind 没结束时间」的半截状态。
    var persistedTimerKindAndEnd: (kind: FocusTimerState.Kind?, end: Date?) {
        switch activeTimerKind {
        case .focus: (.focus, focusTimerEnd)
        case .delayedBlock: (.delayedBlock, delayedBlockEnd)
        case .scheduledBlock: (.scheduledBlock, nil)
        case .none: (nil, nil)
        }
    }

    private func saveFocusTimer() {
        let snapshot = persistedTimerKindAndEnd
        let storage = FocusTimerState(kind: snapshot.kind,
                                      endTimestamp: snapshot.end,
                                      emergencyUsesThisMonth: emergencyUsesThisMonth,
                                      lastResetMonth: lastResetMonth,
                                      delayedBlockPendingAuth: delayedBlockPendingAuth,
                                      delayedBlockRetryCount: delayedBlockRetryCount,
                                      delayedBlockGoal: delayedBlockGoal,
                                      focusTimerGoal: focusTimerGoal,
                                      scheduledExitUsesThisMonth: scheduledExitUsesThisMonth,
                                      focusTimerStart: focusTimerStart,
                                      focusCountdownStart: focusCountdownStart,
                                      breakGlassCooldownEnd: breakGlassCooldownEnd,
                                      breakGlassLastAttemptDay: breakGlassLastAttemptDay,
                                      restActive: restActive,
                                      restEnd: restEnd,
                                      restGoal: restGoal,
                                      restMinutes: restMinutes)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: focusTimerURL)
        } catch {
            FocusLogger.error("saveFocusTimer failed: \(error.localizedDescription)")
            lastError = "保存计时状态失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 定时屏蔽（每天重复的多段时间段）

    func setScheduledWindows(_ windows: [ScheduledWindow]) {
        scheduledWindows = windows
        saveScheduledWindows()
        rescheduleScheduledBlock()
        refreshGoalOverlay()
        FocusLogger.info("setScheduledWindows — \(windows.count) windows")
    }

    func addScheduledWindow(startMinute: Int, endMinute: Int) {
        var list = scheduledWindows
        list.append(ScheduledWindow(id: UUID(), startMinute: startMinute, endMinute: endMinute))
        setScheduledWindows(list)
    }

    func removeScheduledWindow(id: UUID) {
        setScheduledWindows(scheduledWindows.filter { $0.id != id })
    }

    private func saveScheduledWindows() {
        guard let data = try? JSONEncoder().encode(scheduledWindows) else { return }
        settings.set(data, for: .scheduledWindows)
    }

    private func loadScheduledWindows() {
        if let data = settings.data(.scheduledWindows),
           let saved = try? JSONDecoder().decode([ScheduledWindow].self, from: data) {
            scheduledWindows = saved
        }
        releasedOccurrenceKey = settings.string(.scheduledReleasedOccurrenceKey)
        rescheduleScheduledBlock()
    }

    private func setReleasedOccurrence(_ key: String?) {
        releasedOccurrenceKey = key
        settings.set(key, for: .scheduledReleasedOccurrenceKey)
    }

    /// 定期 tick：进入某时间段时确保屏蔽开启；被放弃的时间段过期后清理标记。
    private func rescheduleScheduledBlock() {
        scheduledBlockTask?.cancel()
        scheduledBlockTask = nil
        guard !scheduledWindows.isEmpty else { return }
        scheduledBlockTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.tickScheduledBlock()
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { return }
            }
        }
    }

    private var lastScheduledOccurrenceKey: String?
    /// 用户在「定时到点 vs 延时倒计时」冲突时选择了「继续延时到点」的那次时间段 key。
    /// 该时段内不再反复询问；延时结束/取消后自动补上屏蔽。
    private var scheduledDeferredKey: String?

    private func tickScheduledBlock() {
        purgeExpiredOneTimeWindows()
        let key = activeOccurrenceKey()
        // 已被放弃的时间段已离开 → 清除标记，让后续新时间段可再次硬锁。
        if let released = releasedOccurrenceKey, key != released {
            setReleasedOccurrence(nil)
        }
        // 之前选择「继续延时」的时间段，延时已经结束/被取消 → 解除兜底、补上屏蔽（不再问）。
        if let deferred = scheduledDeferredKey,
           key == deferred,
           !delayedBlockActive,
           key != releasedOccurrenceKey {
            scheduledDeferredKey = nil
            if !blockingEnabled {
                FocusLogger.info("Deferred scheduled window no longer covered by delay — enabling blocking")
                Task { await enableBlocking() }
            }
        }
        // 进入一个新的、未决定的时间段 → 决定是否开屏蔽。
        if let key,
           key != lastScheduledOccurrenceKey,
           key != releasedOccurrenceKey,
           key != scheduledDeferredKey {
            lastScheduledOccurrenceKey = key
            if delayedBlockActive && !blockingEnabled {
                scheduledStartConflictPrompt(key: key)   // 有延时倒计时 → 询问用户
            } else if !blockingEnabled {
                FocusLogger.info("Scheduled block window entered — enabling blocking")
                Task { await enableBlocking() }
            }
        }
        if key == nil {
            lastScheduledOccurrenceKey = nil
            scheduledDeferredKey = nil
        }
    }

    /// 定时屏蔽到点且正有延时倒计时：询问是「立即屏蔽」还是「继续延时到点」。
    private func scheduledStartConflictPrompt(key: String) {
        FocusLogger.info("Scheduled block start while delayed-block counting — asking user")
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "定时屏蔽到点",
            icon: "calendar.badge.clock",
            section1Title: "定时屏蔽已开始",
            message: "你设的定时屏蔽开始了，但延时屏蔽还在倒计时（屏蔽尚未开启）。要现在就屏蔽，还是先继续延时浏览到点？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "立即屏蔽",
            secondaryTitle: "继续延时到点"
        ))
        switch result.choice {
        case .primary:
            // 立即屏蔽：取消延时、立刻开启屏蔽（定时硬锁接管）。
            cancelDelayedBlock()
            Task { await enableBlocking() }
        default:
            // 继续延时到点 / 关闭：保守处理，先不打断延时；该时段不再反复问。
            scheduledDeferredKey = key
        }
    }

    /// 清理已结束的一次性时间段（避免残留、也不再匹配）。
    private func purgeExpiredOneTimeWindows() {
        let now = Date()
        let cal = Calendar.current
        let expired = scheduledWindows.filter { w in
            guard !w.repeats, let day = w.anchorDay else { return false }
            let startMin = cal.startOfDay(for: day)
            let spanMin = w.endMinute > w.startMinute
                ? (w.endMinute - w.startMinute)
                : (24 * 60 + w.endMinute - w.startMinute)
            return now >= startMin.addingTimeInterval(TimeInterval((w.startMinute + spanMin) * 60))
        }
        if !expired.isEmpty {
            let keep = scheduledWindows.filter { w in !expired.contains(where: { $0.id == w.id }) }
            FocusLogger.info("purging \(expired.count) expired one-time scheduled windows")
            setScheduledWindows(keep)
        }
    }

    /// 紧急退出定时屏蔽（密码已在 sheet 验证）：**只**解除本次时间段硬锁（标记放弃），屏蔽保持开启。
    func releaseScheduledLockViaEmergencyExit() {
        guard let key = activeOccurrenceKey() else { return }
        setReleasedOccurrence(key)
        FocusLogger.info("Scheduled block early exit — released occurrence \(key), blocking persists")
    }

    /// 全拦总开关：开启后所有屏蔽状态都屏蔽全部网站 + App。
    func setForceBlockAll(_ on: Bool) {
        forceBlockAll = on
        settings.set(on, for: .forceBlockAll)
        // 若正在屏蔽，重写一遍 hosts + 更新 app 名单，让全拦立即生效。
        if blockingEnabled {
            Task {
                let wasEnabled = blockingEnabled
                isProcessing = true
                do {
                    try await HostsBlocker.apply(domains: effectiveWebsites)
                } catch {
                    lastError = "更新全拦规则失败：\(error.localizedDescription)"
                }
                appBlocker.updateBlockedApps(effectiveApps)
                isProcessing = false
                _ = await save()
                if wasEnabled { onBlockingStateChanged?() }
            }
        } else {
            FocusLogger.info("setForceBlockAll(\(on)) — blocking off, applied on next enable")
        }
    }

    // MARK: - Delayed block timer

    func startDelayedBlock(minutes: Int, goal: String? = nil) {
        guard !restActive else {
            presentNotice("休息中", "请先结束休息，再设置延时屏蔽。")
            return
        }
        guard !blockingEnabled else {
            presentNotice("屏蔽已开启", "屏蔽已经在运行，不需要再设置延时屏蔽。")
            return
        }
        guard !focusTimerActive else {
            presentNotice("专注计时中", "专注计时期间无法启动延时屏蔽。")
            return
        }
        guard !delayedBlockActive else { return }
        delayedBlockRetryCount = 0
        cancelAllNudges()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        delayedBlockEnd = end
        delayedBlockActive = true
        delayedBlockGoal = goal?.isEmpty == true ? nil : goal
        goalOverlayDismissedByUser = false
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.delayedBlockExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Started delayed-block timer: \(minutes) min, ends at \(end)")
    }


    // MARK: - 休息计时

    /// 休息期间遮断其它提醒，结束后再弹一次「休息结束」。
    func startRest(minutes: Int, event: String? = nil) {
        guard !restActive else { return }
        guard minutes > 0 else { return }
        guard blockingEnabled else {
            presentNotice("需要先开启屏蔽", "休息会保持屏蔽状态，所以要先开启屏蔽。")
            return
        }
        guard !focusTimerActive else {
            presentNotice("专注计时中", "先结束当前专注计时，再开始休息。")
            return
        }
        cancelAllNudges()
        stopFocusEndReminder()
        stopBlockingNoFocusLoop()
        restTimerEngine.stop()
        restActive = true
        restEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        restGoal = event?.isEmpty == true ? nil : event
        restMinutes = minutes
        // 休息开始时重置「用户已手动关闭浮窗」标记，保证休息一定有浮窗。
        goalOverlayDismissedByUser = false
        restTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.restExpired() }
        }
        restTimerEngine.start(endTimestamp: restEnd!)
        refreshGoalOverlay()
        FocusLogger.info("Rest started: \(minutes) min, ends at \(restEnd!)")
        if restLockScreen {
            lockScreen()
        }
    }

    func cancelRest() {
        guard restActive else { return }
        restTimerEngine.stop()
        restActive = false
        restEnd = nil
        restGoal = nil
        saveFocusTimer()
        refreshGoalOverlay()

        // 本函数由 SwiftUI 按钮手势回调同步调用（FocusTimerView 的「结束休息」）。
        // 若在同一个手势栈里直接 NSApp.runModal，嵌套模态事件循环会立刻接管 runloop，
        // 按钮手势收不到完整事件序列（mouse-up → gesture 结束 → action 派发），
        // action 闭包永远不执行——表现为「弹窗出现了但点了没反应」。
        // 推迟到下一个 runloop turn，等手势栈完全退出后再启动模态循环。
        if remindRestManualEnd {
            DispatchQueue.main.async { [weak self] in
                self?.presentRestEndReminder()
            }
        }
        // 休息开始时循环已被停止；结束后必须恢复，否则“已屏蔽未专注”不会再提醒。
        restartBlockingNoFocusIfNeeded()
    }

    func restExpired() {
        FocusLogger.info("Rest timer expired")
        restActive = false
        restEnd = nil
        restGoal = nil
        restTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
        presentRestEndReminder()
        // 休息开始时循环已被停止；结束后必须恢复，否则“已屏蔽未专注”不会再提醒。
        restartBlockingNoFocusIfNeeded()
    }

    private func presentRestEndReminder() {
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "休息结束",
            icon: "cup.and.saucer.fill",
            section1Title: "休息好了",
            message: "休息一下，接下来是继续专注，还是再休息一会儿都会尊重你。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            showModePicker: true,
            elapsedPrimaryTitle: "开始正计时",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒",
            showRest: true,
            restTitle: "再休息一会儿",
            restPlaceholder: "休息时想做什么？",
            restDefaultMinutes: 6,
            showHints: false,
            showTextHint: true
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .elapsed:
            startFocusTimerElapsed(goal: result.goal)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            scheduleNudge(seconds: TimeInterval(blockingNoFocusIntervalMinutes * 60), task: &focusEndNudgeTask) { [weak self] in
                guard let self, !self.focusTimerActive else { return }
                self.presentRestEndReminder()
            }
        default:
            break
        }
    }

    /// 专注计时/延时屏蔽期间显示悬浮窗（无论是否填写事件），
    /// 事件可选、倒计时可选（专注计时是否显示时间由设置控制）。
    /// 尊重用户对当前会话的一次性关闭。
    private func refreshGoalOverlay() {
        let shouldShow = (restActive || focusTimerActive || delayedBlockActive) && !goalOverlayDismissedByUser
        FocusLogger.info("refreshGoalOverlay — rest\(restActive) focus\(focusTimerActive) delayed\(delayedBlockActive) dismissed\(goalOverlayDismissedByUser) → \(shouldShow ? "show" : "hide")")
        guard shouldShow else {
            goalOverlay.hide()
            return
        }
        let title: String
        let goal = activeGoal
        let end: Date?
        let elapsedStart: Date?
        if restActive {
            title = "休息中"
            end = restEnd
            elapsedStart = nil
        } else if focusTimerActive {
            title = isElapsedFocus ? "正计时中" : "专注计时中"
            if isElapsedFocus {
                end = nil
                elapsedStart = focusTimerStart
            } else {
                end = focusOverlayShowsTime ? focusTimerEnd : nil
                elapsedStart = nil
            }
        } else {
            title = "延时屏蔽中"
            end = delayedBlockEnd
            elapsedStart = nil
        }
        goalOverlay.show(title: title, goal: goal, end: end, elapsedStart: elapsedStart) { [weak self] in
            self?.goalOverlayDismissedByUser = true
            self?.goalOverlay.hide()
        }
    }

    func delayedBlockExpired() {
        FocusLogger.info("Delayed-block timer expired naturally")
        delayedBlockActive = false
        delayedBlockEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()

        // Lock screen at expiry regardless of whether the subsequent admin auth succeeds —
        // the user's intent with delayedBlockLockScreen is "lock when timer ends", not "lock
        // only if blocking also installs cleanly". Doing this before the alert means the user
        // returns to an already-locked screen and then sees the choice dialog.
        if delayedBlockLockScreen {
            lockScreen()
        }

        // The first expiry shows a decision prompt so the user may consume their
        // extension before blocking starts. Once the extension is unavailable,
        // expiry auto-blocks; the post-block reminder is shown by enableBlocking().
        let canStillExtend = delayedBlockAllowExtension && delayedBlockRetryCount < 1

        if canStillExtend {
            guard beginReminderModal() else {
                Task { await attemptDelayedBlockEnable(initialAlert: false) }
                return
            }
            defer { endReminderModal() }

            let presets: [(String, Int)] = [("再等 5 分钟", 5), ("再等 10 分钟", 10)]
            let result = PromptPanelPresenter.run(PromptPanelConfig(
                title: "延时屏蔽时间到",
                icon: "clock.badge.exclamationmark",
                section1Title: "屏蔽准备完成",
                message: "倒计时已结束。现在开启屏蔽，或延长一次作为最后缓冲。",
                subtitle: "可延长 1 次",
                tone: .warning,
                presets: presets,
                actionItems: actionPrompts.filter { $0.text != "暂停一下" },
                textItems: textPrompts,
                primaryTitle: "立即屏蔽",
                primaryTint: .focusAccent,
                primaryHint: "不需要延长？",
                durationConfirmTitle: "确认延长",
                showPause: false
            ))

            switch result.choice {
            case .preset(let minutes):
                extendDelayedBlock(minutes: minutes)
            case .custom(let minutes) where minutes > 0:
                extendDelayedBlock(minutes: minutes)
            default:
                // Close / invalid custom means block now, not an escape hatch.
                Task { await attemptDelayedBlockEnable(initialAlert: true) }
            }
        } else {
            Task { await attemptDelayedBlockEnable(initialAlert: true) }
        }
    }

    func blockNow() {
        guard delayedBlockActive else { return }
        FocusLogger.info("blockNow — skipping delayed-block countdown, attempting to enable blocking")
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockGoal = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
        Task { await attemptDelayedBlockEnable(initialAlert: true) }
    }

    private func lockScreen() {
        // Launch ScreenSaverEngine instead of synthesizing Control+Command+Q via CGEvent.
        // Why: CGEvent requires Accessibility permission, and ad-hoc signed binaries
        // get a fresh cdhash every rebuild — TCC treats each rebuild as a new app and
        // silently revokes the grant, so the keyboard shortcut never fires.
        // ScreenSaverEngine needs no permission and works on all macOS versions;
        // lock depends on the user's "require password after screensaver" setting,
        // which is the default.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "ScreenSaverEngine"]
        do {
            try task.run()
            FocusLogger.info("lockScreen: ScreenSaverEngine launched")
        } catch {
            FocusLogger.error("lockScreen: failed to launch ScreenSaverEngine — \(error.localizedDescription)")
            lastError = "锁屏失败：无法启动 ScreenSaverEngine（\(error.localizedDescription)）"
        }
    }

    /// Cancelling a delayed block is a deliberate escape from the future block,
    /// so route it through the same password sheet used for other destructive actions.
    func requestCancelDelayedBlock() {
        guard delayedBlockActive else { return }
        guard hasPassword else {
            presentNotice("需要先设置屏蔽密码", "取消延时计时需要通过密码验证，请先在设置里设置屏蔽密码。")
            showSettingsSheet = true
            return
        }

        pendingActionLabel = "取消延时计时"
        pendingToggleAction = { [weak self] in
            self?.cancelDelayedBlock()
        }
        showPasswordSheet = true
    }

    func cancelDelayedBlock() {
        guard delayedBlockActive else { return }
        FocusLogger.info("cancelDelayedBlock — clearing delayed-block timer without enabling blocking")
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockGoal = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
    }

    /// Called when delayed-block timer expires (or via "立即授权" retry button).
    /// Tries to enable blocking; on success clears all pending state.
    /// On failure (user cancelled admin prompt) sets pendingAuth and pops
    /// the global NSAlert (immediate on first expiry, 30s-scheduled on retry failure).
    func attemptDelayedBlockEnable(initialAlert: Bool = false) async {
        await enableBlocking()
        if blockingEnabled {
            FocusLogger.info("Delayed-block enable succeeded — clearing pending state")
            delayedBlockPendingAuth = false
            delayedBlockRetryCount = 0
            delayedBlockNextRetryAt = nil
            delayedBlockGoal = nil
            stopPendingAlertLoop()
            saveFocusTimer()
            refreshGoalOverlay()
            // Note: lockScreen() (if enabled) already fired at expiry in delayedBlockExpired(),
            // before this alert was shown. Don't re-lock here.
            return
        }
        // Failed — user cancelled admin prompt
        FocusLogger.info("Delayed-block enable failed (user cancelled) — retryCount=\(delayedBlockRetryCount)")
        delayedBlockPendingAuth = true
        saveFocusTimer()
        stopPendingAlertLoop()
        if initialAlert {
            presentExtendAlert()
        } else {
            scheduleNextPendingAlert()
        }
    }

    /// Extend the timer (user picked 5 or 10 min). Consumes one extension.
    /// Called when the first expiry prompt chooses a delay; after that, expiry auto-blocks.
    func extendDelayedBlock(minutes: Int) {
        guard delayedBlockRetryCount < 1 else { return }
        delayedBlockRetryCount += 1
        delayedBlockPendingAuth = false
        stopPendingAlertLoop()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        delayedBlockEnd = end
        delayedBlockActive = true
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.delayedBlockExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        refreshGoalOverlay()
        FocusLogger.info("Extended delayed-block by \(minutes) min (used \(delayedBlockRetryCount)/2), new end=\(end)")
    }

    /// User-initiated retry from pending state — re-runs the admin prompt.
    func retryDelayedBlockNow() {
        guard delayedBlockPendingAuth else { return }
        FocusLogger.info("retryDelayedBlockNow — user-initiated retry")
        Task { await attemptDelayedBlockEnable(initialAlert: false) }
    }

    // MARK: - Pending-alert loop (global NSAlert that re-pops every 30s)

    private var pendingAlertTask: Task<Void, Never>?
    private var pendingAlertInFlight = false

    /// Pop the global NSAlert immediately. Modal — blocks main thread until user responds.
    /// After dismissal, if still pending, schedules a 30s re-pop.
    func presentExtendAlert() {
        // 有一个调用点在 SwiftUI `Button` 的 action 里（FocusTimerView 的「立即打开弹窗」），
        // 手势栈未退出时弹模态会锁死 runloop。统一推迟一个 turn。
        DialogPanelFactory.runDeferred { [weak self] in
            self?.performPresentExtendAlert()
        }
    }

    /// `presentExtendAlert` 的真正实现。已保证不在 SwiftUI 手势栈里执行。
    private func performPresentExtendAlert() {
        guard delayedBlockPendingAuth else { return }
        guard !pendingAlertInFlight else { return }
        pendingAlertInFlight = true
        stopPendingAlertLoop()

        guard beginReminderModal() else {
            pendingAlertInFlight = false
            scheduleNextPendingAlert()
            return
        }
        defer {
            pendingAlertInFlight = false
            endReminderModal()
        }

        let canExtend = delayedBlockRetryCount < 1
        let subtitle = "到点未成功开启屏蔽，请选择。" + (canExtend ? "（还可延长 1 次）" : "（延长次数已用完）")
        let presets: [(String, Int)] = canExtend
            ? [("再等 5 分钟", 5), ("再等 10 分钟", 10)]
            : []

        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "屏蔽未生效",
            icon: "exclamationmark.triangle.fill",
            section1Title: "授权需要确认",
            message: subtitle,
            subtitle: "上一次系统授权没有完成",
            tone: .danger,
            presets: presets,
            actionItems: actionPrompts.filter { $0.text != "暂停一下" },
            textItems: textPrompts,
            primaryTitle: "立即授权",
            durationConfirmTitle: canExtend ? "确认延长" : nil,
            showPause: false
        ))

        switch result.choice {
        case .preset(let minutes):
            extendDelayedBlock(minutes: minutes)
        case .custom(let minutes) where minutes > 0:
            extendDelayedBlock(minutes: minutes)
        case .pause:
            break
        default:
            retryDelayedBlockNow()
        }

        // If still pending after handling, schedule the 30s re-pop.
        if delayedBlockPendingAuth {
            scheduleNextPendingAlert()
        }
    }

    /// Schedule a 30s-delayed re-pop of the alert. Cancels any previously scheduled pop.
    func scheduleNextPendingAlert() {
        pendingAlertTask?.cancel()
        guard delayedBlockPendingAuth else { return }
        delayedBlockNextRetryAt = Date().addingTimeInterval(30)
        pendingAlertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { return }
            guard self.delayedBlockPendingAuth else { return }
            self.presentExtendAlert()
        }
    }

    private func stopPendingAlertLoop() {
        pendingAlertTask?.cancel()
        pendingAlertTask = nil
        delayedBlockNextRetryAt = nil
    }

    /// Pending-auth alerts restored at launch must wait until AppKit has finished setup.
    private func scheduleStartupPendingAlert() {
        pendingAlertTask?.cancel()
        pendingAlertTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.presentExtendAlert()
        }
    }

    func save() async -> Bool {
        let storage = SettingsStorage(blockRules: blockRules)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: settingsURL)
        } catch {
            FocusLogger.error("save settings failed: \(error.localizedDescription)")
            lastError = "保存设置失败：\(error.localizedDescription)"
            return false
        }
        settings.set(blockingEnabled, for: .blockingEnabled)
        settings.set(launchAtLogin, for: .launchAtLogin)

        appBlocker.updateBlockedApps(effectiveApps)
        appBlocker.setBlockingEnabled(blockingEnabled)

        if blockingEnabled && helperInstalled {
            let domains = effectiveWebsites
            do {
                if domains.isEmpty {
                    try await HostsBlocker.clear()
                } else {
                    try await HostsBlocker.apply(domains: domains)
                }
                lastError = nil
            } catch {
                FocusLogger.error("HostsBlocker apply failed: \(error.localizedDescription)")
                lastError = "更新屏蔽规则失败：\(error.localizedDescription)"
                return false
            }
        }
        return true
    }

    func setPassword(_ password: String) {
        guard !isLocked else {
            presentNotice("专注计时中", "专注计时期间无法修改屏蔽密码。")
            return
        }
        do {
            try KeychainPassword.save(password)
            hasPassword = !password.isEmpty
            FocusLogger.info("Password set/changed")
        } catch {
            FocusLogger.error("KeychainPassword.save failed: \(error.localizedDescription)")
            lastError = "密码保存失败：\(error.localizedDescription)"
        }
    }

    /// Verify password before changing to new one
    func changePassword(oldPassword: String, newPassword: String) {
        guard !isLocked else {
            presentNotice("专注计时中", "专注计时期间无法修改屏蔽密码。")
            return
        }
        guard KeychainPassword.verify(oldPassword) else { return }
        setPassword(newPassword)
    }

    func enableBlocking() async {
        // Install helper if not already installed (one-time admin prompt)
        if (!helperInstalled || helperNeedsRepair) && !helperInstallAttempted {
            helperInstallAttempted = true

            // 与其它弹窗共用同一套外观（DialogShell 白卡 + 主题色按钮），不再用系统 NSAlert。
            let choice = NoticeDialogPresenter.run(NoticeDialogView(
                title: "需要一次性授权",
                icon: "lock.shield",
                message: "Focus&Pause 需要安装后台助手来静默更新屏蔽规则。",
                highlights: [
                    "这只需授权一次，之后所有屏蔽操作都会在后台静默执行。",
                    "点击「好」后会弹出系统密码输入框。",
                ],
                actions: [
                    .init(title: "取消") {},
                    .init(title: "好", isPrimary: true) {},
                ]
            ))
            if choice == 1 {
                isInstallingHelper = true
                let ok = await HelperInstaller.install()
                if ok {
                    await probeHelperAfterInstall()
                } else {
                    FocusLogger.info("Helper install failed — falling back to per-op osascript")
                    helperInstallAttempted = false
                }
                isInstallingHelper = false
            } else {
                FocusLogger.info("User cancelled helper install")
                helperInstallAttempted = false
            }
        }

        FocusLogger.info("enableBlocking — websites=\(effectiveWebsites.count), apps=\(effectiveApps.count), forceBlockAll=\(forceBlockAll)")
        isProcessing = true
        onBlockingStateChanged?()
        let domains = effectiveWebsites
        if !domains.isEmpty {
            do {
                try await HostsBlocker.apply(domains: domains)
                blockingEnabled = true
                appBlocker.setBlockingEnabled(true)
                lastError = nil
            } catch {
                FocusLogger.error("enableBlocking failed: \(error.localizedDescription)")
                lastError = "屏蔽失败：\(error.localizedDescription)"
                isProcessing = false
                onBlockingStateChanged?()
                return
            }
        } else {
            blockingEnabled = true
            appBlocker.setBlockingEnabled(true)
        }
        await appBlocker.enforceNow()
        isProcessing = false
        onBlockingStateChanged?()
        restartReminderIfNeeded()
        _ = await save()
        startBlockingCooldown()
        presentFocusTimerReminder()
        // Another pass after the reminder closes covers apps the user reopened
        // while the modal was on screen.
        await appBlocker.enforceNow()
    }

    /// Start the cooldown timer after blocking is enabled (if enabled in settings).
    /// Also schedules an auto-expiry that clears `coolDownEndsAt` when the cooldown
    /// elapses. Without it, the countdown hits 0 but no @Published value changes,
    /// so SwiftUI never re-renders: the UI stays frozen on "00:00" with the
    /// stop-blocking button disabled until the user switches tabs.
    private func startBlockingCooldown() {
        cooldownTask?.cancel()
        if coolingEnabled && coolingMinutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(coolingMinutes * 60))
            coolDownEndsAt = end
            cooldownTask = Task { @MainActor [weak self] in
                let remaining = end.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining + 0.5))
                }
                guard !Task.isCancelled else { return }
                if self?.coolDownEndsAt == end {
                    self?.coolDownEndsAt = nil
                }
            }
        } else {
            coolDownEndsAt = nil
        }
    }

    func disableBlocking() async {
        guard !restActive else {
            presentNotice("休息中", "请先结束休息，再解除屏蔽。")
            return
        }
        guard coolDownRemaining <= 0 else {
            presentNotice("冷静期中", "冷静期内无法解除屏蔽，剩余 \(Int(coolDownRemaining) / 60) 分 \(Int(coolDownRemaining) % 60) 秒。")
            return
        }
        guard !isScheduledLockActive else {
            presentNotice("定时屏蔽中", "请先在「计时模式 → 定时屏蔽」页面紧急退出，或等到时间段结束。")
            return
        }
        FocusLogger.info("disableBlocking")
        isProcessing = true
        onBlockingStateChanged?()
        do {
            try await HostsBlocker.clear()
            blockingEnabled = false
            appBlocker.setBlockingEnabled(false)
            lastError = nil
        } catch {
            FocusLogger.error("disableBlocking failed: \(error.localizedDescription)")
            lastError = "停止失败：\(error.localizedDescription)"
            isProcessing = false
            onBlockingStateChanged?()
            return
        }
        isProcessing = false
        onBlockingStateChanged?()
        cooldownTask?.cancel()
        stopFocusEndReminder()
        coolDownEndsAt = nil
        restartReminderIfNeeded()
        _ = await save()
        presentDelayedBlockReminder()
    }

    func toggleBlocking() {
        // 4 个调用点里有 4 个是 SwiftUI `Button` 的 action。手势栈未退出时弹模态会锁死
        // runloop（详见 presentNotice 的注释），所以整个流程推迟一个 runloop turn。
        // 菜单栏右键那条调用路径本来就在 AppKit 事件里，推迟一 turn 也没有副作用。
        DialogPanelFactory.runDeferred { [weak self] in
            self?.performToggleBlocking()
        }
    }

    /// `toggleBlocking` 的真正实现。已保证不在 SwiftUI 手势栈里执行。
    private func performToggleBlocking() {
        guard coolDownRemaining <= 0 else {
            showCooldownAlert = true
            return
        }
        // 定时屏蔽硬锁窗口内：点停止 → 只提示，退出需到「计时模式 → 定时屏蔽」页走紧急退出。
        if blockingEnabled && isScheduledLockActive {
            presentNotice(
                "定时屏蔽进行中",
                "当前时间段内屏蔽已锁定。要提前结束，请到「计时模式 → 定时屏蔽」页面使用紧急退出。"
            )
            return
        }
        if delayedBlockActive {
            blockNow()
            return
        }
        guard !isLocked else {
            presentNotice(
                restActive ? "休息中" : "专注计时中",
                restActive
                    ? "休息期间屏蔽已锁定，请先结束休息再修改屏蔽状态。"
                    : "专注计时期间屏蔽已锁定，需结束计时或紧急退出后才能修改。"
            )
            return
        }
        if blockingEnabled {
            if !hasPassword {
                Task { await disableBlocking() }
            } else {
                pendingToggleAction = { [weak self] in Task { await self?.disableBlocking() } }
                pendingActionLabel = "解除屏蔽"
                showPasswordSheet = true
            }
        } else if !hasPassword {
            // 与其它弹窗统一外观的自绘提示（原来用 NSAlert，按钮配色和主界面不一致）。
            let choice = NoticeDialogPresenter.run(NoticeDialogView(
                title: "建议设置屏蔽密码",
                icon: "key.fill",
                message: "你还没有设置密码。没有密码的话，任何人点「停止屏蔽」都能直接关闭。",
                highlights: [
                    "建议现在设置，给关闭屏蔽增加一点操作摩擦。",
                    "也可以稍后再说，先在「设置 → 密码」里补上。",
                ],
                actions: [
                    .init(title: "稍后再说") {},
                    .init(title: "设置密码", isPrimary: true) {},
                ]
            ))
            if choice == 1 {
                showSettingsSheet = true
                return
            }
            Task { await enableBlocking() }
        } else {
            Task { await enableBlocking() }
        }
    }

    /// 安装/重启 helper 后 LaunchDaemon 需要一点时间才起来，最多重试 3 次。
    /// 成功即返回；始终不健康则更新 helperInstalled/helperNeedsRepair 并置 lastError。
    private func probeHelperAfterInstall() async {
        for i in 0..<3 {
            try? await Task.sleep(for: .seconds(1))
            let running = await HelperConnection.shared.forceProbe()
            helperInstalled = running
            helperNeedsRepair = running && !HelperInstaller.tokenPermissionsAreSecure()
            if running && !helperNeedsRepair { return }
            FocusLogger.info("Helper probe retry \(i+1)/3 failed")
        }
        FocusLogger.info("Helper installed but probe/permission check failed after retries")
        helperInstallAttempted = false
        lastError = "后台助手安装后仍需修复，请稍后重试。"
    }

    func installHelper() async {
        guard !isInstallingHelper else { return }
        guard !helperInstalled || helperNeedsRepair else { return }
        helperInstallAttempted = true
        isInstallingHelper = true
        let ok = await HelperInstaller.install()
        if ok {
            await probeHelperAfterInstall()
        } else {
            FocusLogger.info("Helper install failed")
            helperInstallAttempted = false
            lastError = "助手安装失败，请稍后重试"
        }
        isInstallingHelper = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            FocusLogger.info("Launch at login set to \(enabled)")
        } catch {
            FocusLogger.error("setLaunchAtLogin failed: \(error.localizedDescription)")
            lastError = "设置开机启动失败：\(error.localizedDescription)"
        }
        Task { _ = await save() }
    }

    func quitCleanup() {
        FocusLogger.info("quitCleanup")
        appBlocker.stop()
        focusTimerEngine.stop()
        cooldownTask?.cancel()
        scheduledBlockTask?.cancel()
        stopFocusEndReminder()
        stopPendingAlertLoop()
        stopReminderLoop()
        stopBlockingNoFocusLoop()
        // Don't clear hosts — let blocking persist across quit
        // Don't reset focusTimerActive/delayedBlock* — timer survives by endTimestamp
    }

    // MARK: - Reminder

    func setReminderEnabled(_ enabled: Bool) {
        reminderEnabled = enabled
        settings.set(enabled, for: .reminderEnabled)
        if enabled {
            startReminderLoop()
        } else {
            stopReminderLoop()
        }
    }

    func setReminderInterval(minutes: Int) {
        var v = minutes
        if v < 1 { v = 1 }
        reminderIntervalMinutes = v
        settings.set(v, for: .reminderIntervalMinutes)
        restartReminderIfNeeded()
    }

    func setCoolingEnabled(_ enabled: Bool) {
        coolingEnabled = enabled
        settings.set(enabled, for: .coolingEnabled)
        if !enabled {
            cooldownTask?.cancel()
            coolDownEndsAt = nil
        }
    }

    func setCoolingMinutes(_ minutes: Int) {
        var v = minutes
        if v < 1 { v = 1 }
        coolingMinutes = v
        settings.set(v, for: .coolingMinutes)
    }

    func setFocusOverlayShowsTime(_ shows: Bool) {
        focusOverlayShowsTime = shows
        settings.set(shows, for: .focusOverlayShowsTime)
        refreshGoalOverlay()
    }

    func setDelayedBlockLockScreen(_ enabled: Bool) {
        delayedBlockLockScreen = enabled
        settings.set(enabled, for: .delayedBlockLockScreen)
    }

    func setDelayedBlockAllowExtension(_ enabled: Bool) {
        delayedBlockAllowExtension = enabled
        settings.set(enabled, for: .delayedBlockAllowExtension)
    }

    func setRemindFocusTimerAfterEnd(_ enabled: Bool) {
        remindFocusTimerAfterEnd = enabled
        settings.set(enabled, for: .remindFocusTimerAfterEnd)
        if !enabled {
            stopFocusEndReminder()
        }
    }

    func setRemindCountdownManualEnd(_ enabled: Bool) {
        remindCountdownManualEnd = enabled
        settings.set(enabled, for: .remindCountdownManualEnd)
    }

    func setRemindRestManualEnd(_ enabled: Bool) {
        remindRestManualEnd = enabled
        settings.set(enabled, for: .remindRestManualEnd)
    }

    func setRestLockScreen(_ enabled: Bool) {
        restLockScreen = enabled
        settings.set(enabled, for: .restLockScreen)
    }

    func setAccentTheme(_ theme: AccentTheme) {
        accentTheme = theme
        settings.set(theme.rawValue, for: .accentTheme)
    }

    func setAppearanceTheme(_ theme: AppearanceTheme) {
        appearanceTheme = theme
        settings.set(theme.rawValue, for: .appearanceTheme)
    }

    func setRemindFocusTimerAfterBlock(_ enabled: Bool) {
        remindFocusTimerAfterBlock = enabled
        settings.set(enabled, for: .remindFocusTimerAfterBlock)
    }

    func setRemindDelayedBlockAfterUnblock(_ enabled: Bool) {
        remindDelayedBlockAfterUnblock = enabled
        settings.set(enabled, for: .remindDelayedBlockAfterUnblock)
    }

    func setRemindBlockingNoFocus(_ enabled: Bool) {
        remindBlockingNoFocus = enabled
        settings.set(enabled, for: .remindBlockingNoFocus)
        if enabled {
            startBlockingNoFocusLoop()
        } else {
            stopBlockingNoFocusLoop()
        }
    }

    func setBlockingNoFocusInterval(minutes: Int) {
        var v = minutes
        if v < 1 { v = 1 }
        blockingNoFocusIntervalMinutes = v
        settings.set(v, for: .blockingNoFocusIntervalMinutes)
        restartBlockingNoFocusIfNeeded()
    }

    /// 通用的条件轮询骨架：条件不满足时按 `retryDelay` 短睡后重试，满足时按
    /// `interval` 等待后执行 `action`；执行前会再检查一次条件，避免睡眠期间
    /// 状态已变化却仍然弹窗。任务取消即退出。
    ///
    /// - Parameters:
    ///   - interval: 条件满足时，两次触发之间的间隔（秒）。
    ///   - retryDelay: 条件不满足时的短睡间隔（秒），避免空转烧电。
    ///   - shouldRun: 触发前与长睡前各检查一次。
    ///   - action: 实际触发逻辑。
    private func startConditionalPolling(
        interval: TimeInterval,
        retryDelay: TimeInterval = 30,
        shouldRun: @escaping @MainActor () -> Bool,
        action: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                guard shouldRun() else {
                    try? await Task.sleep(for: .seconds(retryDelay))
                    continue
                }
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                guard shouldRun() else { continue }
                action()
            }
        }
    }

    private func startReminderLoop() {
        stopReminderLoop()
        guard reminderEnabled else { return }
        reminderTask = startConditionalPolling(
            interval: TimeInterval(reminderIntervalMinutes * 60),
            // 抽取前，长睡后的第二次检查漏了 delayedBlockPendingAuth，导致「屏蔽未生效」
            // 的授权重试弹窗在屏时可能又弹一个「未屏蔽提醒」。两处检查现已统一为同一条件。
            shouldRun: { [weak self] in self?.reminderLoopShouldRun ?? false },
            action: { [weak self] in self?.presentReminderAlert() }
        )
    }

    /// 「未屏蔽提醒」循环的触发条件。长睡前后必须是同一组条件，且要给其它提醒弹窗让位。
    var reminderLoopShouldRun: Bool {
        reminderEnabled
            && !blockingEnabled
            && !focusTimerActive
            && !delayedBlockActive
            && !delayedBlockPendingAuth
            && !reminderModalInFlight
    }

    private func stopReminderLoop() {
        reminderTask?.cancel()
        reminderTask = nil
        reminderNudgeTask?.cancel()
        reminderNudgeTask = nil
    }

    private func restartReminderIfNeeded() {
        // Restart to pick up new state (interval change or blocking state change)
        if reminderEnabled { startReminderLoop() }
    }

    /// 「稍后提醒」：间隔后强制再弹一次（不论对应开关是否开启）。由 inFlight 与主循环去重。
    private func scheduleNudge(seconds: TimeInterval, task: inout Task<Void, Never>?, run: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            run()
        }
    }

    /// 清除所有「稍后提醒」的一次性调度（开始专注/延时等后不再弹过期的 offer）。
    private func cancelAllNudges() {
        reminderNudgeTask?.cancel(); reminderNudgeTask = nil
        blockingNoFocusNudgeTask?.cancel(); blockingNoFocusNudgeTask = nil
        focusEndNudgeTask?.cancel(); focusEndNudgeTask = nil
        focusTimerReminderNudgeTask?.cancel(); focusTimerReminderNudgeTask = nil
        delayedBlockNudgeTask?.cancel(); delayedBlockNudgeTask = nil
    }

    private func presentReminderAlert() {
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "未屏蔽提醒",
            icon: "bell",
            section1Title: "延时屏蔽计时",
            message: "已经 \(reminderIntervalMinutes) 分钟没开屏蔽啦。现在开，或设个延时到点自动挡，都行。",
            presets: [("5 分钟", 5), ("10 分钟", 10), ("30 分钟", 30)],
            showGoal: true,
            goalPlaceholder: "这段时间想做什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "立即屏蔽",
            primaryTint: .focusAccent,
            primaryHint: "不需要延时？",
            durationConfirmTitle: "延时屏蔽计时",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒"
        ))
        switch result.choice {
        case .preset(let minutes):
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .primary:
            Task { await enableBlocking() }   // 立即屏蔽
        case .pause:
            openPractice(.toolbox)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            // 稍后提醒：设置开着→主循环已按间隔覆盖，无需额外调度器；关着→安排一次 nudge。
            if reminderEnabled { break }
            scheduleNudge(seconds: TimeInterval(reminderIntervalMinutes * 60), task: &reminderNudgeTask) { [weak self] in
                guard let self, !self.blockingEnabled else { return }   // 未屏蔽提醒仅在仍处于未屏蔽时重弹
                self.presentReminderAlert()
            }
        default:
            break   // 取消 → 按设置来：开关开则主循环继续、关则停
        }
    }

    // MARK: - 已屏蔽但未专注计时提醒

    private func startBlockingNoFocusLoop() {
        stopBlockingNoFocusLoop()
        guard remindBlockingNoFocus else { return }
        blockingNoFocusTask = startConditionalPolling(
            interval: TimeInterval(blockingNoFocusIntervalMinutes * 60),
            shouldRun: { [weak self] in self?.blockingNoFocusLoopShouldRun ?? false },
            action: { [weak self] in self?.presentBlockingNoFocusAlert() }
        )
    }

    /// 「已屏蔽未专注」循环的触发条件。
    ///
    /// `reminderModalInFlight` 这条不能少：之前只挡了专注结束那一类。上一个提醒弹窗
    /// 关闭时闸已释放，轮询醒来条件又全部满足，于是紧跟着再弹一个，两个弹窗叠在一起
    /// ——主线程卡在嵌套 `runModal` 里，界面看起来就是彻底卡死。
    var blockingNoFocusLoopShouldRun: Bool {
        remindBlockingNoFocus
            && blockingEnabled
            && !restActive
            && !focusTimerActive
            && !delayedBlockActive
            && !delayedBlockPendingAuth
            && !isFocusEndNagging
            && !reminderModalInFlight
    }

    private func stopBlockingNoFocusLoop() {
        blockingNoFocusTask?.cancel()
        blockingNoFocusTask = nil
        blockingNoFocusNudgeTask?.cancel()
        blockingNoFocusNudgeTask = nil
    }

    private func restartBlockingNoFocusIfNeeded() {
        if remindBlockingNoFocus { startBlockingNoFocusLoop() }
    }

    private func presentBlockingNoFocusAlert() {
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "已屏蔽未专注",
            icon: "lock.open",
            section1Title: "专注计时",
            message: "屏蔽正开着，正是专注的好时候。倒计时一段，或不限时地投入，都行。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            showModePicker: true,
            elapsedPrimaryTitle: "开始正计时",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒",
            showRest: true,
            restTitle: "休息一下",
            restPlaceholder: "休息时想做什么？",
            restDefaultMinutes: 6,
            showHints: false,
            showTextHint: true
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .elapsed:
            startFocusTimerElapsed(goal: result.goal)   // 正计时
        case .pause:
            openPractice(.toolbox)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            if remindBlockingNoFocus { break }   // 循环已覆盖，不额外调度
            scheduleNudge(seconds: TimeInterval(blockingNoFocusIntervalMinutes * 60), task: &blockingNoFocusNudgeTask) { [weak self] in
                // 已屏蔽未专注仅在「屏蔽中且未专注」时重弹
                guard let self, self.blockingEnabled, !self.focusTimerActive else { return }
                self.presentBlockingNoFocusAlert()
            }
        default:
            break   // 取消 → 按设置来
        }
    }

    // MARK: - 屏蔽后 / 解除后提醒


    // MARK: - 专注计时结束后继续提醒

    /// Starts periodic nagging after a focus timer ends naturally (if enabled),
    /// asking whether to start another session. Stops when a new timer starts,
    /// blocking is disabled, the user declines for this session, or the toggle
    /// is turned off. Cadence reuses the global reminder interval.
    private func startFocusEndReminderLoop() {
        stopFocusEndReminder()
        guard remindFocusTimerAfterEnd else { return }
        // 专注结束的「稍后提醒」接管此状态的提醒，让「已屏蔽但未专注」循环让位
        isFocusEndNagging = true
        focusEndReminderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.remindFocusTimerAfterEnd,
                      !self.focusTimerActive,
                      self.blockingEnabled,
                      !self.delayedBlockActive,
                      !self.delayedBlockPendingAuth else { break }
                self.presentFocusEndReminder()
                if Task.isCancelled { break }
                // 「稍后提醒」复用「已屏蔽未专注」的间隔
                let interval = self.blockingNoFocusIntervalMinutes * 60
                try? await Task.sleep(for: .seconds(interval))
            }
            // 循环自然退出（条件不再满足）时恢复「已屏蔽但未专注」提醒能力
            self.isFocusEndNagging = false
        }
    }

    func stopFocusEndReminder() {
        isFocusEndNagging = false
        focusEndReminderTask?.cancel()
        focusEndReminderTask = nil
        focusEndNudgeTask?.cancel()
        focusEndNudgeTask = nil
    }

    private func presentFocusEndReminder() {
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "专注计时已结束",
            icon: "timer",
            section1Title: "专注计时",
            message: "这一轮结束啦。休息好了就回来，再来一段，或不限时地继续。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            showModePicker: true,
            elapsedPrimaryTitle: "开始正计时",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒",
            showRest: true,
            restTitle: "休息一下",
            restPlaceholder: "休息时想做什么？",
            restDefaultMinutes: 6,
            restBeforeFocus: true,
            showHints: false,
            showTextHint: true
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .elapsed:
            startFocusTimerElapsed(goal: result.goal)   // 正计时
        case .pause:
            openPractice(.toolbox)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            if remindFocusTimerAfterEnd { break }   // 循环已覆盖，不额外调度
            scheduleNudge(seconds: TimeInterval(blockingNoFocusIntervalMinutes * 60), task: &focusEndNudgeTask) { [weak self] in
                // 专注结束提醒仅在「无专注且屏蔽中」时重弹
                guard let self, !self.focusTimerActive, self.blockingEnabled else { return }
                self.presentFocusEndReminder()
            }
        default:
            break                             // 取消 → 按设置来
        }
    }

    private func presentFocusTimerReminder() {
        guard remindFocusTimerAfterBlock else { return }
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "屏蔽已开启",
            icon: "lock.open",
            section1Title: "专注计时",
            message: "干扰已经挡在外面啦，现在就来一段专注吧。倒计时或不限时，都按你喜欢。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            showModePicker: true,
            elapsedPrimaryTitle: "开始正计时",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒",
            showRest: true,
            restTitle: "休息一下",
            restPlaceholder: "休息时想做什么？",
            restDefaultMinutes: 6,
            showHints: false,
            showTextHint: true
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .elapsed:
            startFocusTimerElapsed(goal: result.goal)   // 正计时
        case .pause:
            openPractice(.toolbox)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            if remindBlockingNoFocus { break }   // 已屏蔽未专注的循环已覆盖该状态
            scheduleNudge(seconds: TimeInterval(blockingNoFocusIntervalMinutes * 60), task: &focusTimerReminderNudgeTask) { [weak self] in
                // 屏蔽已开启仅在「仍在屏蔽且未专注」时重弹；否则说明已解除，交给未屏蔽提醒。
                guard let self, self.blockingEnabled, !self.focusTimerActive else { return }
                self.presentFocusTimerReminder()
            }
        default:
            break
        }
    }

    private func presentDelayedBlockReminder() {
        guard remindDelayedBlockAfterUnblock else { return }
        guard !focusTimerActive else { return }
        guard beginReminderModal() else { return }
        defer { endReminderModal() }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "屏蔽已停止",
            icon: "clock",
            section1Title: "延时屏蔽",
            message: "想自由一会儿，又怕分心？设个延时，到点自动帮你把干扰挡回去。",
            presets: [("5 分钟", 5), ("10 分钟", 10), ("30 分钟", 30)],
            showGoal: true,
            goalPlaceholder: "这段时间想做什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            secondaryTitle: "取消",
            tertiaryTitle: "稍后提醒"
        ))
        switch result.choice {
        case .preset(let minutes):
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .pause:
            openPractice(.toolbox)
        case .grounding:
            openPractice(.grounding)
        case .rest(let minutes):
            startRest(minutes: minutes, event: result.restEvent)
        case .tertiary:
            if reminderEnabled { break }   // 未屏蔽提醒的循环已覆盖该状态
            scheduleNudge(seconds: TimeInterval(reminderIntervalMinutes * 60), task: &delayedBlockNudgeTask) { [weak self] in
                // 屏蔽已停止仅在「仍处于未屏蔽」时重弹；否则说明已重新屏蔽，交给其他提醒。
                guard let self, !self.blockingEnabled else { return }
                self.presentDelayedBlockReminder()
            }
        default:
            break
        }
    }

    // MARK: - 正念

    /// 从弹窗跳转到练习页：切到「暂停一下」标签、落到对应子模式，并呼起主窗口。
    func openPractice(_ mode: PauseMode) {
        pauseMode = mode
        selectedTab = 2
        onOpenMainWindow?()
    }

    /// 文字提示（弹窗里仅展示、不可点）。
    var textPrompts: [PromptItem] {
        prompts.filter { $0.kind == .text }
    }

    /// 动作提示（弹窗里可点、触发练习）。
    var actionPrompts: [PromptItem] {
        prompts.filter { $0.kind == .action }
    }

    func addPrompt(text: String, kind: PromptItem.Kind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompts.append(PromptItem(kind: kind, text: trimmed))
        savePrompts()
    }

    func updatePrompt(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].text = trimmed
        savePrompts()
    }

    func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        savePrompts()
    }

    func movePrompt(id: UUID, up: Bool) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard target >= 0 && target < prompts.count else { return }
        prompts.swapAt(index, target)
        savePrompts()
    }

    private func savePrompts() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        settings.set(data, for: .prompts)
    }

    private func loadPrompts() {
        if let data = settings.data(.prompts),
           let saved = try? JSONDecoder().decode([PromptItem].self, from: data),
           !saved.isEmpty {
            prompts = saved
            return
        }
        // 迁移上一版「鼓励语」卡片，保留用户已写文案。
        if let data = settings.data(.encouragementCards),
           let saved = try? JSONDecoder().decode([EncouragementCard].self, from: data),
           !saved.isEmpty {
            prompts = saved.map { PromptItem(kind: .text, text: $0.text) }
            savePrompts()
            return
        }
        prompts = [
            PromptItem(kind: .text, text: "喝口水吧"),
            PromptItem(kind: .text, text: "站起来走走"),
            PromptItem(kind: .text, text: "上个厕所"),
            PromptItem(kind: .action, text: "暂停一下"),
            PromptItem(kind: .action, text: "五感着陆"),
        ]
    }

    // MARK: - 暂停工具箱分组与链接

    func addToolboxGroup(name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        toolboxGroups.append(ToolboxGroup(name: n, links: []))
        saveToolboxGroups()
    }

    func renameToolboxGroup(id: UUID, name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty,
              let index = toolboxGroups.firstIndex(where: { $0.id == id }) else { return }
        toolboxGroups[index].name = n
        saveToolboxGroups()
    }

    func deleteToolboxGroup(id: UUID) {
        toolboxGroups.removeAll { $0.id == id }
        saveToolboxGroups()
    }

    func addToolboxLink(groupID: UUID, title: String, url: String, kind: ToolboxLink.Kind = .link) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = normalizeToolboxURL(url, kind: kind)
        guard !t.isEmpty, !u.isEmpty,
              let index = toolboxGroups.firstIndex(where: { $0.id == groupID }) else { return }
        toolboxGroups[index].links.append(ToolboxLink(title: t, url: u, kind: kind))
        saveToolboxGroups()
    }

    func updateToolboxLink(linkID: UUID, title: String, url: String, kind: ToolboxLink.Kind = .link) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = normalizeToolboxURL(url, kind: kind)
        guard !t.isEmpty, !u.isEmpty,
              let gIndex = toolboxGroups.firstIndex(where: { $0.links.contains { $0.id == linkID } }),
              let lIndex = toolboxGroups[gIndex].links.firstIndex(where: { $0.id == linkID }) else { return }
        toolboxGroups[gIndex].links[lIndex].title = t
        toolboxGroups[gIndex].links[lIndex].url = u
        toolboxGroups[gIndex].links[lIndex].kind = kind
        saveToolboxGroups()
    }

    /// 外链补 https:// 前缀；本机应用路径原样保留（不补 scheme）。
    private func normalizeToolboxURL(_ url: String, kind: ToolboxLink.Kind) -> String {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .link else { return clean }
        return normalizedURL(clean)
    }

    /// 打开一条工具箱项：网页外链走浏览器，本机应用用 NSWorkspace 启动。
    func openToolboxItem(_ link: ToolboxLink) {
        switch link.kind {
        case .link:
            if let u = URL(string: link.url) {
                NSWorkspace.shared.open(u)
            }
        case .app:
            guard FileManager.default.fileExists(atPath: link.url) else {
                lastError = "找不到应用「\(link.title)」（\(link.url)）"
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: link.url))
        }
    }

    func deleteToolboxLink(groupID: UUID, linkID: UUID) {
        guard let gIndex = toolboxGroups.firstIndex(where: { $0.id == groupID }) else { return }
        toolboxGroups[gIndex].links.removeAll { $0.id == linkID }
        saveToolboxGroups()
    }

    func moveToolboxLink(groupID: UUID, linkID: UUID, up: Bool) {
        guard let gIndex = toolboxGroups.firstIndex(where: { $0.id == groupID }),
              let lIndex = toolboxGroups[gIndex].links.firstIndex(where: { $0.id == linkID }) else { return }
        let target = up ? lIndex - 1 : lIndex + 1
        guard target >= 0 && target < toolboxGroups[gIndex].links.count else { return }
        toolboxGroups[gIndex].links.swapAt(lIndex, target)
        saveToolboxGroups()
    }

    /// 补齐缺少的 https:// 前缀。
    private func normalizedURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }

    private func saveToolboxGroups() {
        guard let data = try? JSONEncoder().encode(toolboxGroups) else { return }
        settings.set(data, for: .toolboxGroups)
    }

    private func loadToolboxLinks() {
        if let data = settings.data(.toolboxGroups),
           let saved = try? JSONDecoder().decode([ToolboxGroup].self, from: data),
           !saved.isEmpty {
            var groups = saved
            // 合并旧扁平数据里缺失的链接（幂等：按 id 或 标题|地址 判重，只补缺失项）
            if let flatData = settings.data(.toolboxLinks),
               let flat = try? JSONDecoder().decode([ToolboxLink].self, from: flatData) {
                let existingIDs = Set(groups.flatMap { $0.links.map(\.id) })
                let existingPairs = Set(groups.flatMap { $0.links.map { "\($0.title)|\($0.url)" } })
                let missing = flat.filter {
                    !existingIDs.contains($0.id)
                        && !existingPairs.contains("\($0.title)|\($0.url)")
                }
                if !missing.isEmpty {
                    groups.append(ToolboxGroup(name: "常用", links: missing))
                    saveToolboxGroups()
                }
            }
            toolboxGroups = groups
            return
        }
        // 迁移上一版扁平链接：收进一个分组
        if let data = settings.data(.toolboxLinks),
           let saved = try? JSONDecoder().decode([ToolboxLink].self, from: data),
           !saved.isEmpty {
            toolboxGroups = [ToolboxGroup(name: "常用", links: saved)]
            saveToolboxGroups()
            return
        }
        // 首次启动的默认示例：用户可随时增删改，之后以自己的修改为准。
        toolboxGroups = [
            ToolboxGroup(name: "常用", links: [
                ToolboxLink(title: "去暂停工具箱",
                            url: "https://ebp.gesedna.com/pa-pause-tool/?utm_source=gese_pauselab&utm_medium=wechat_menu&rd=%2FEBPTask%2F"),
            ]),
            ToolboxGroup(name: "小练习", links: [
                ToolboxLink(title: "去动力激活",
                            url: "https://ebp.gesedna.com/pa-motivation-improve/?rd=%2Fpa-pause-tool"),
                ToolboxLink(title: "去情绪降温",
                            url: "https://ebp.gesedna.com/pa-toolbox-emo-landing-listen/?rd=%2Fpa-emotion-cool-down%2F%2F%3Frd%3D%2Fpa-pause-tool"),
                ToolboxLink(title: "去正念呼吸",
                            url: "https://ebp.gesedna.com/pa-toolbox-recharge-mindfulnessbreath-listen/?rd=%2Fpa-recharge%2F%2F%3Frd%3D%2Fpa-pause-tool"),
            ]),
        ]
    }
}

/// 枚举本机已安装的 `.app`（名字 + 绝对路径），供工具箱选「本机应用」。
enum InstalledApps {
    static func installed() -> [(name: String, path: String)] {
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/System/Applications",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        var result: [(name: String, path: String)] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let full = "\(dir)/\(item)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = String(item.dropLast(4))
                if name == "FocusPause" || name == "Focus&Pause" { continue }   // 排除自身
                result.append((name, full))
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.path).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct SettingsStorage: Codable {
    let blockRules: [BlockRule]
}
