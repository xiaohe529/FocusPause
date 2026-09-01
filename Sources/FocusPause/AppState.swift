import Foundation
import AppKit
import ApplicationServices
import ServiceManagement
import CoreGraphics

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var blockingEnabled = false
    @Published var blockRules: [BlockRule] = []
    @Published var hasPassword = false
    /// The version the user chose to ignore in the update prompt; nag again only
    /// when a newer version appears.
    var ignoredUpdateVersion: String? {
        get { UserDefaults.standard.string(forKey: "ignoredUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "ignoredUpdateVersion") }
    }
    @Published var showPasswordSheet = false
    @Published var pendingToggleAction: (() -> Void)?
    @Published var pendingActionLabel: String = ""
    @Published var lastError: String?
    @Published var isProcessing = false
    @Published var launchAtLogin = false
    @Published var wifiDisabled = false
    @Published var focusTimerActive = false
    @Published var focusTimerEnd: Date? = nil
    @Published var emergencyUsesThisMonth = 0
    @Published var showEmergencyOverrideSheet = false
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
    /// 全拦总开关：开启后任何屏蔽状态都屏蔽全部网站 + App，忽略每条规则的开关。
    @Published var forceBlockAll = false

    // 正念：导航状态（弹窗可编程切页）+ 鼓励语
    enum PauseMode {
        case breathing
        case grounding
        case cards
    }
    @Published var selectedTab = 0
    @Published var pauseMode: PauseMode = .breathing
    @Published var prompts: [PromptItem] = []
    @Published var toolboxGroups: [ToolboxGroup] = []

    /// 弹窗跳转到练习页时，用来呼起主窗口。
    var onOpenMainWindow: (() -> Void)?

    private var reminderTask: Task<Void, Never>?
    private var reminderAlertInFlight = false
    private var cooldownTask: Task<Void, Never>?
    private var focusEndReminderTask: Task<Void, Never>?
    private var focusEndReminderInFlight = false
    /// 专注计时结束的「稍后提醒」循环进行中时为 true，让「已屏蔽但未专注」循环让位，避免两个提醒同时弹。
    private var isFocusEndNagging = false
    /// 定时屏蔽的起止调度任务：start 前等待、到点开启。
    private var scheduledBlockTask: Task<Void, Never>?
    private var blockingNoFocusTask: Task<Void, Never>?
    private var blockingNoFocusInFlight = false

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
    private let goalOverlay = GoalOverlayController()
    private var goalOverlayDismissedByUser = false

    /// 专注计时「紧急退出」每月额度（用户可设 1–5，默认 3；每月仅可改一次）。
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
            lastError = "本月已设置过专注紧急退出额度，下个月才能再改"
            return false
        }
        emergencyQuota = min(5, max(1, value))
        lastEmergencyQuotaSetMonth = month
        UserDefaults.standard.set(emergencyQuota, forKey: "emergencyQuota")
        UserDefaults.standard.set(month, forKey: "emergencyQuotaSetMonth")
        FocusLogger.info("Emergency quota set to \(emergencyQuota) for \(month)")
        return true
    }

    /// 设置定时屏蔽紧急退出额度。本月已设过则拒绝并返回 false。
    @discardableResult
    func setScheduledExitQuota(_ value: Int) -> Bool {
        let month = Self.currentMonthString()
        if lastScheduledQuotaSetMonth == month {
            lastError = "本月已设置过定时屏蔽退出额度，下个月才能再改"
            return false
        }
        scheduledExitQuota = min(5, max(1, value))
        lastScheduledQuotaSetMonth = month
        UserDefaults.standard.set(scheduledExitQuota, forKey: "scheduledExitQuota")
        UserDefaults.standard.set(month, forKey: "scheduledExitQuotaSetMonth")
        FocusLogger.info("Scheduled-exit quota set to \(scheduledExitQuota) for \(month)")
        return true
    }

    private var lastResetMonth: String = ""

    var isLocked: Bool { focusTimerActive }

    /// 屏蔽名单处于锁定状态（专注计时中 / 屏蔽开启中）时返回提示文案，否则 nil。
    func ruleListLockedError() -> String? {
        if isLocked { return "专注计时中，屏蔽名单已锁定，无法删除条目" }
        if blockingEnabled { return "屏蔽开启中，屏蔽名单已锁定，无法删除条目" }
        return nil
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
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: now)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        for w in scheduledWindows where w.enabled {
            if w.repeats {
                if let k = activeKeyForDaily(w, now: now, cal: cal, minute: minute) { return (w, k) }
            } else if let k = activeKeyForOneTime(w, now: now, cal: cal) { return (w, k) }
        }
        return nil
    }

    /// 每天重复：按当日时间匹配，归属日 = 开始当天（跨午夜时凌晨段归前一天）。
    private func activeKeyForDaily(_ w: ScheduledWindow, now: Date, cal: Calendar, minute: Int) -> String? {
        let overnight = w.endMinute < w.startMinute
        if !overnight {
            if minute >= w.startMinute && minute < w.endMinute {
                return Self.occurrenceKey(w, day: cal.startOfDay(for: now))
            }
        } else if minute >= w.startMinute {                       // 跨午夜：晚上段
            return Self.occurrenceKey(w, day: cal.startOfDay(for: now))
        } else if minute < w.endMinute {                          // 跨午夜：次日凌晨段
            let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
            return Self.occurrenceKey(w, day: yesterday)
        }
        return nil
    }

    /// 一次性：只在 anchorDay 那一次开机范围内有效。
    private func activeKeyForOneTime(_ w: ScheduledWindow, now: Date, cal: Calendar) -> String? {
        guard let day = w.anchorDay else { return nil }
        let startMin = cal.startOfDay(for: day)
        let start = startMin.addingTimeInterval(TimeInterval(w.startMinute * 60))
        let spanMin = w.endMinute > w.startMinute
            ? (w.endMinute - w.startMinute)
            : (24 * 60 + w.endMinute - w.startMinute)
        let end = start.addingTimeInterval(TimeInterval(spanMin * 60))
        guard now >= start && now < end else { return nil }
        return Self.occurrenceKey(w, day: startMin)
    }

    private static func occurrenceKey(_ w: ScheduledWindow, day: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(w.id.uuidString)|\(fmt.string(from: day))"
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

    /// The goal for whichever session is currently active (focus timer or
    /// delayed block), shown in the floating always-on-top overlay.
    private var activeGoal: String? {
        if focusTimerActive { return focusTimerGoal }
        if delayedBlockActive { return delayedBlockGoal }
        return nil
    }

    // MARK: - 有效屏蔽规则（受全拦总开关影响）

    /// 实际用于屏蔽的网站域名：全拦开启时忽略每条规则开关。
    var effectiveWebsites: [String] {
        blockRules.filter { $0.type == .website && (forceBlockAll || $0.enabled) }.map { $0.name }
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

        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        if let enabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool {
            blockingEnabled = enabled
        }
        forceBlockAll = UserDefaults.standard.bool(forKey: "forceBlockAll")
        loadScheduledWindows()
        if let q = UserDefaults.standard.object(forKey: "emergencyQuota") as? Int {
            emergencyQuota = min(5, max(1, q))
        }
        if let q = UserDefaults.standard.object(forKey: "scheduledExitQuota") as? Int {
            scheduledExitQuota = min(5, max(1, q))
        }
        lastEmergencyQuotaSetMonth = UserDefaults.standard.string(forKey: "emergencyQuotaSetMonth")
        lastScheduledQuotaSetMonth = UserDefaults.standard.string(forKey: "scheduledExitQuotaSetMonth")
        delayedBlockLockScreen = UserDefaults.standard.bool(forKey: "delayedBlockLockScreen")
        delayedBlockAllowExtension = UserDefaults.standard.object(forKey: "delayedBlockAllowExtension") as? Bool ?? true
        focusOverlayShowsTime = UserDefaults.standard.object(forKey: "focusOverlayShowsTime") as? Bool ?? true

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
            self.helperInstalled = await HelperInstaller.isInstalledAndRunning()
            if !self.helperInstalled {
                FocusLogger.info("Helper not installed — skipping blocking restore on launch")
                if self.blockingEnabled {
                    self.blockingEnabled = false
                    self.appBlocker.setBlockingEnabled(false)
                }
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

        reminderEnabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
        let storedInterval = UserDefaults.standard.object(forKey: "reminderIntervalMinutes") as? Int
        reminderIntervalMinutes = storedInterval ?? 30
        if reminderIntervalMinutes < 1 { reminderIntervalMinutes = 1 }
        startReminderLoop()

        remindBlockingNoFocus = UserDefaults.standard.bool(forKey: "remindBlockingNoFocus")
        let storedBNF = UserDefaults.standard.object(forKey: "blockingNoFocusIntervalMinutes") as? Int
        blockingNoFocusIntervalMinutes = storedBNF ?? 30
        if blockingNoFocusIntervalMinutes < 1 { blockingNoFocusIntervalMinutes = 1 }
        startBlockingNoFocusLoop()

        coolingEnabled = UserDefaults.standard.bool(forKey: "coolingEnabled")
        let storedCooling = UserDefaults.standard.object(forKey: "coolingMinutes") as? Int
        coolingMinutes = storedCooling ?? 5
        if coolingMinutes < 1 { coolingMinutes = 1 }
        remindFocusTimerAfterBlock = UserDefaults.standard.object(forKey: "remindFocusTimerAfterBlock") as? Bool ?? true
        remindDelayedBlockAfterUnblock = UserDefaults.standard.object(forKey: "remindDelayedBlockAfterUnblock") as? Bool ?? true
        remindFocusTimerAfterEnd = UserDefaults.standard.object(forKey: "remindFocusTimerAfterEnd") as? Bool ?? false

        loadPrompts()
        loadToolboxLinks()

        FocusLogger.info("AppState load complete — blockingEnabled=\(blockingEnabled) hasPassword=\(hasPassword)")
    }

    /// 一次性迁移：开发阶段曾用「裸二进制」运行（UserDefaults 域 = 进程名 FocusPause），
    /// 而打包 .app 的域是 com.focuspause.app，两边配置可能各存一份。
    /// 首次以 .app 运行时，把旧域的键复制进当前域（当前域已有的键不覆盖）。
    private func migrateLegacyDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "didMigrateLegacyDefaults") else { return }
        UserDefaults.standard.set(true, forKey: "didMigrateLegacyDefaults")
        guard let legacy = UserDefaults(suiteName: "FocusPause") else { return }
        let keys = [
            "prompts", "toolboxLinks", "toolboxGroups",
            "reminderEnabled", "reminderIntervalMinutes",
            "coolingEnabled", "coolingMinutes",
            "remindFocusTimerAfterBlock", "remindDelayedBlockAfterUnblock", "remindFocusTimerAfterEnd",
            "remindBlockingNoFocus", "blockingNoFocusIntervalMinutes",
            "launchAtLogin", "blockingEnabled",
            "delayedBlockLockScreen", "delayedBlockAllowExtension",
            "focusOverlayShowsTime",
            "ignoredUpdateVersion",
        ]
        var migrated = false
        for key in keys {
            guard UserDefaults.standard.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            UserDefaults.standard.set(value, forKey: key)
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

        // Reset transient timer state — will be repopulated below
        focusTimerActive = false
        focusTimerEnd = nil
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockPendingAuth = false
        delayedBlockRetryCount = 0
        delayedBlockNextRetryAt = nil
        delayedBlockGoal = loaded.delayedBlockGoal
        focusTimerGoal = loaded.focusTimerGoal

        // Resume active timer if end is still in the future
        if let end = loaded.endTimestamp, end > Date() {
            let kind = loaded.kind ?? .focus
            switch kind {
            case .focus:
                focusTimerEnd = end
                focusTimerActive = true
                focusTimerEngine.onExpire = { [weak self] in
                    Task { @MainActor in self?.focusTimerExpired() }
                }
                FocusLogger.info("Resumed active focus timer, ends at \(end)")
            case .delayedBlock:
                delayedBlockEnd = end
                delayedBlockActive = true
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
            // Pop the alert immediately on restart — global nag
            presentExtendAlert()
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
        guard !delayedBlockActive else {
            lastError = "延时屏蔽进行中，无法启动专注计时"
            return
        }
        guard blockingEnabled else {
            lastError = "请先开启屏蔽再启动专注计时"
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        stopFocusEndReminder()
        focusTimerEnd = end
        focusTimerActive = true
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

    func focusTimerExpired() {
        FocusLogger.info("Focus timer expired naturally")
        focusTimerActive = false
        focusTimerEnd = nil
        focusTimerGoal = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        refreshGoalOverlay()
        startFocusEndReminderLoop()
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
            focusTimerGoal = nil
            focusTimerEngine.stop()
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
            lastError = "本月定时屏蔽紧急退出次数已用完"
            FocusLogger.error("Scheduled exit rejected: quota exhausted (\(scheduledExitUsesThisMonth)/\(scheduledExitQuota))")
            return false
        }
        scheduledExitUsesThisMonth += 1
        releaseScheduledLockViaEmergencyExit()
        saveFocusTimer()   // 持久化月度额度
        FocusLogger.info("Scheduled emergency exit used \(scheduledExitUsesThisMonth)/\(scheduledExitQuota)")
        return true
    }

    private func saveFocusTimer() {
        let storage = FocusTimerState(kind: activeTimerKind,
                                      endTimestamp: activeTimerKind != nil ? (focusTimerActive ? focusTimerEnd : delayedBlockEnd) : nil,
                                      emergencyUsesThisMonth: emergencyUsesThisMonth,
                                      lastResetMonth: lastResetMonth,
                                      delayedBlockPendingAuth: delayedBlockPendingAuth,
                                      delayedBlockRetryCount: delayedBlockRetryCount,
                                      delayedBlockGoal: delayedBlockGoal,
                                      focusTimerGoal: focusTimerGoal,
                                      scheduledExitUsesThisMonth: scheduledExitUsesThisMonth)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: focusTimerURL)
        } catch {
            FocusLogger.error("saveFocusTimer failed: \(error.localizedDescription)")
            lastError = "保存计时状态失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 定时屏蔽（每天重复的多段时间段）

    private let scheduledWindowsKey = "scheduledWindows"
    private let scheduledReleasedKey = "scheduledReleasedOccurrenceKey"

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
        UserDefaults.standard.set(data, forKey: scheduledWindowsKey)
    }

    private func loadScheduledWindows() {
        if let data = UserDefaults.standard.data(forKey: scheduledWindowsKey),
           let saved = try? JSONDecoder().decode([ScheduledWindow].self, from: data) {
            scheduledWindows = saved
        }
        releasedOccurrenceKey = UserDefaults.standard.string(forKey: scheduledReleasedKey)
        rescheduleScheduledBlock()
    }

    private func setReleasedOccurrence(_ key: String?) {
        releasedOccurrenceKey = key
        UserDefaults.standard.set(key, forKey: scheduledReleasedKey)
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
        UserDefaults.standard.set(on, forKey: "forceBlockAll")
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
        guard !blockingEnabled else {
            lastError = "屏蔽已开启，无需延时屏蔽"
            return
        }
        guard !focusTimerActive else {
            lastError = "专注计时进行中，无法启动延时屏蔽"
            return
        }
        guard !delayedBlockActive else { return }
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

    /// 专注计时/延时屏蔽期间显示悬浮窗（无论是否填写事件），
    /// 事件可选、倒计时可选（专注计时是否显示时间由设置控制）。
    /// 尊重用户对当前会话的一次性关闭。
    private func refreshGoalOverlay() {
        let shouldShow = (focusTimerActive || delayedBlockActive) && !goalOverlayDismissedByUser
        FocusLogger.info("refreshGoalOverlay — focus\(focusTimerActive) delayed\(delayedBlockActive) dismissed\(goalOverlayDismissedByUser) → \(shouldShow ? "show" : "hide")")
        guard shouldShow else {
            goalOverlay.hide()
            return
        }
        let title = focusTimerActive ? "专注计时中" : "延时屏蔽中"
        let goal = activeGoal
        let end: Date?
        if delayedBlockActive {
            end = delayedBlockEnd
        } else {
            end = focusOverlayShowsTime ? focusTimerEnd : nil
        }
        goalOverlay.show(title: title, goal: goal, end: end) { [weak self] in
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

        // Extension is only useful when the user still has retries left. Once they've used
        // their one extension, the next expiry auto-blocks — no point popping an alert
        // whose only button is "立即屏蔽".
        let canStillExtend = delayedBlockAllowExtension && delayedBlockRetryCount < 1

        if canStillExtend {
            let presets: [(String, Int)] = [("再等 5 分钟", 5), ("再等 10 分钟", 10)]
            let (choice, _) = durationAlert(
                title: "延时屏蔽时间到",
                message: "倒计时已结束。（可延长 1 次）",
                goalPlaceholder: nil,
                style: .warning,
                icon: "clock.badge.exclamationmark",
                prefix: ["立即屏蔽"],
                presets: presets,
                customButtonTitle: "自定义时长")
            switch choice {
            case .prefix:
                Task { await attemptDelayedBlockEnable(initialAlert: true) }
            case .preset(let index):
                extendDelayedBlock(minutes: presets[index].1)
            case .custom(let minutes) where minutes > 0:
                extendDelayedBlock(minutes: minutes)
            default:
                // ESC / invalid custom — treat as 立即屏蔽 to avoid escape loophole
                Task { await attemptDelayedBlockEnable(initialAlert: true) }
            }
        } else {
            // Either extension disabled, or extension used up — auto-block, no alert.
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

    /// Extend the timer after expiry (user picked 5 or 10 min). Consumes one of 2 allowed extensions.
    /// Called from both natural-expiry path (delayedBlockExpired → user picks "再等 5 分钟")
    /// and pending-auth path (presentExtendAlert → user picks "再等 5 分钟").
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
        guard delayedBlockPendingAuth else { return }
        guard !pendingAlertInFlight else { return }
        pendingAlertInFlight = true
        stopPendingAlertLoop()

        var subtitle = "到点未成功开启屏蔽，请选择："
        if delayedBlockRetryCount < 1 {
            subtitle += "（还可延长 1 次）"
        } else {
            subtitle += "（延长次数已用完）"
        }

        if delayedBlockRetryCount < 1 {
            let presets: [(String, Int)] = [("再等 5 分钟", 5), ("再等 10 分钟", 10)]
            let (choice, _) = durationAlert(
                title: "屏蔽未生效",
                message: subtitle,
                goalPlaceholder: nil,
                style: .warning,
                icon: "exclamationmark.triangle.fill",
                presets: presets,
                customButtonTitle: "自定义时长",
                extras: ["立即授权"])
            pendingAlertInFlight = false
            switch choice {
            case .preset(let index):
                extendDelayedBlock(minutes: presets[index].1)
            case .custom(let minutes) where minutes > 0:
                extendDelayedBlock(minutes: minutes)
            default:
                retryDelayedBlockNow()  // 立即授权 / ESC / invalid custom
            }
        } else {
            _ = durationAlert(
                title: "屏蔽未生效",
                message: subtitle,
                goalPlaceholder: nil,
                style: .warning,
                icon: "exclamationmark.triangle.fill",
                presets: [],
                extras: ["立即授权"])
            pendingAlertInFlight = false
            retryDelayedBlockNow()
        }

        // If still pending after handling, schedule 30s re-pop
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
        UserDefaults.standard.set(blockingEnabled, forKey: "blockingEnabled")
        UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")

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
            lastError = "专注计时中，无法修改密码"
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
            lastError = "专注计时中，无法修改密码"
            return
        }
        guard KeychainPassword.verify(oldPassword) else { return }
        setPassword(newPassword)
    }

    func enableBlocking() async {
        // Install helper if not already installed (one-time admin prompt)
        if !helperInstalled && !helperInstallAttempted {
            helperInstallAttempted = true

            // Show explanation before the admin prompt
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            alert.messageText = "需要一次性授权"
            alert.informativeText = "FocusPause 需要安装后台助手来静默更新屏蔽规则，避免每次操作都弹出密码框。\n\n这只需授权一次，之后所有屏蔽操作都会在后台静默执行。\n\n点击「好」后将弹出系统密码输入框。"
            alert.addButton(withTitle: "好")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                isInstallingHelper = true
                let ok = await HelperInstaller.install()
                if ok {
                    for i in 0..<3 {
                        try? await Task.sleep(for: .seconds(1))
                        helperInstalled = await HelperConnection.shared.forceProbe()
                        if helperInstalled { break }
                        FocusLogger.info("Helper probe retry \(i+1)/3 failed")
                    }
                    if !helperInstalled {
                        FocusLogger.info("Helper installed but probe failed after retries — will retry later")
                        helperInstallAttempted = false
                    }
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
        isProcessing = false
        onBlockingStateChanged?()
        restartReminderIfNeeded()
        _ = await save()
        startBlockingCooldown()
        presentFocusTimerReminder()
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
        guard coolDownRemaining <= 0 else {
            lastError = "冷静期内无法解除屏蔽，剩余 \(Int(coolDownRemaining) / 60) 分 \(Int(coolDownRemaining) % 60) 秒"
            return
        }
        guard !isScheduledLockActive else {
            lastError = "定时屏蔽中，请先结束定时屏蔽（密码）或等到点解除硬锁"
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
        guard coolDownRemaining <= 0 else {
            showCooldownAlert = true
            return
        }
        // 定时屏蔽硬锁窗口内：点停止 → 只提示，退出需到「计时模式 → 定时屏蔽」页走紧急退出。
        if isScheduledLockActive {
            lastError = "定时屏蔽中，请在「计时模式 → 定时屏蔽」页面使用紧急退出"
            return
        }
        guard !isLocked else {
            lastError = "专注计时中，无法修改屏蔽状态"
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
            // Proactively remind user to set a password before enabling blocking
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
            alert.messageText = "建议设置屏蔽密码"
            alert.informativeText = "你还没有设置密码。没有密码的话，任何人点击「停止屏蔽」都可以直接关闭，之前忍住的冲动可能一秒破功。\n\n建议现在设置，给关闭屏蔽增加一点操作摩擦。"
            alert.addButton(withTitle: "设置密码")
            alert.addButton(withTitle: "稍后再说")
            if alert.runModal() == .alertFirstButtonReturn {
                showSettingsSheet = true
                return
            }
            Task { await enableBlocking() }
        } else {
            Task { await enableBlocking() }
        }
    }

    func installHelper() async {
        guard !helperInstalled else { return }
        helperInstallAttempted = true
        isInstallingHelper = true
        let ok = await HelperInstaller.install()
        if ok {
            for i in 0..<3 {
                try? await Task.sleep(for: .seconds(1))
                helperInstalled = await HelperConnection.shared.forceProbe()
                if helperInstalled { break }
                FocusLogger.info("Helper probe retry \(i+1)/3 failed")
            }
            if !helperInstalled {
                FocusLogger.info("Helper installed but probe failed after retries")
                helperInstallAttempted = false
            }
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
        UserDefaults.standard.set(enabled, forKey: "reminderEnabled")
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
        UserDefaults.standard.set(v, forKey: "reminderIntervalMinutes")
        restartReminderIfNeeded()
    }

    func setCoolingEnabled(_ enabled: Bool) {
        coolingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "coolingEnabled")
        if !enabled {
            cooldownTask?.cancel()
            coolDownEndsAt = nil
        }
    }

    func setCoolingMinutes(_ minutes: Int) {
        var v = minutes
        if v < 1 { v = 1 }
        coolingMinutes = v
        UserDefaults.standard.set(v, forKey: "coolingMinutes")
    }

    func setFocusOverlayShowsTime(_ shows: Bool) {
        focusOverlayShowsTime = shows
        UserDefaults.standard.set(shows, forKey: "focusOverlayShowsTime")
        refreshGoalOverlay()
    }

    func setRemindBlockingNoFocus(_ enabled: Bool) {
        remindBlockingNoFocus = enabled
        UserDefaults.standard.set(enabled, forKey: "remindBlockingNoFocus")
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
        UserDefaults.standard.set(v, forKey: "blockingNoFocusIntervalMinutes")
        restartBlockingNoFocusIfNeeded()
    }

    private func startReminderLoop() {
        stopReminderLoop()
        guard reminderEnabled else { return }
        reminderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Skip if any blocking state active
                guard self.reminderEnabled,
                      !self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive,
                      !self.delayedBlockPendingAuth else {
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                let interval = self.reminderIntervalMinutes * 60
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                guard self.reminderEnabled,
                      !self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive else { continue }
                self.presentReminderAlert()
            }
        }
    }

    private func stopReminderLoop() {
        reminderTask?.cancel()
        reminderTask = nil
    }

    private func restartReminderIfNeeded() {
        // Restart to pick up new state (interval change or blocking state change)
        if reminderEnabled { startReminderLoop() }
    }

    private func presentReminderAlert() {
        guard !reminderAlertInFlight else { return }
        reminderAlertInFlight = true
        defer { reminderAlertInFlight = false }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "未屏蔽提醒",
            icon: "bell",
            section1Title: "延时屏蔽计时",
            message: "您已经 \(reminderIntervalMinutes) 分钟没开启屏蔽了。可立即屏蔽，或设一个时长延时屏蔽，到点自动开启。",
            presets: [("5 分钟", 5), ("10 分钟", 10), ("30 分钟", 30)],
            showGoal: true,
            goalPlaceholder: "这段时间想做什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "延时屏蔽计时",
            secondaryTitle: "立即屏蔽",
            tertiaryTitle: "稍后提醒"
        ))
        switch result.choice {
        case .preset(let minutes):
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .secondary:
            Task { await enableBlocking() }   // 立即屏蔽
        case .pause:
            openPractice(.breathing)
        default:
            break   // 稍后提醒 → 循环继续，间隔后再次提醒
        }
    }

    // MARK: - 已屏蔽但未专注计时提醒

    private func startBlockingNoFocusLoop() {
        stopBlockingNoFocusLoop()
        guard remindBlockingNoFocus else { return }
        blockingNoFocusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // 只在「屏蔽中且无专注计时」时计时，其他状态短睡跳过
                guard self.remindBlockingNoFocus,
                      self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive,
                      !self.delayedBlockPendingAuth,
                      !self.isFocusEndNagging else {
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                let interval = self.blockingNoFocusIntervalMinutes * 60
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                guard self.remindBlockingNoFocus,
                      self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive,
                      !self.isFocusEndNagging else { continue }
                self.presentBlockingNoFocusAlert()
            }
        }
    }

    private func stopBlockingNoFocusLoop() {
        blockingNoFocusTask?.cancel()
        blockingNoFocusTask = nil
    }

    private func restartBlockingNoFocusIfNeeded() {
        if remindBlockingNoFocus { startBlockingNoFocusLoop() }
    }

    private func presentBlockingNoFocusAlert() {
        guard !blockingNoFocusInFlight else { return }
        blockingNoFocusInFlight = true
        defer { blockingNoFocusInFlight = false }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "已屏蔽未专注",
            icon: "lock.open",
            section1Title: "专注计时",
            message: "屏蔽已开启，但还没有开始专注计时。选个时长，现在就开始吧。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            secondaryTitle: "稍后提醒"
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .pause:
            openPractice(.breathing)
        default:
            break   // 稍后提醒 → 循环继续，间隔后再次提醒
        }
    }

    // MARK: - 屏蔽后 / 解除后提醒

    /// The choice from a `durationAlert`, resolved against its button list.
    private enum DurationChoice {
        case prefix(Int)       // 0-based index into leading buttons
        case preset(Int)       // 0-based index into preset buttons
        case custom(minutes: Int)  // the custom button; minutes 0 if unparseable
        case extra(Int)        // 0-based index into trailing buttons
    }

    /// Alert with optional goal + custom-minutes fields and duration buttons.
    /// Button order: prefix, presets, [customButtonTitle], extras.
    private func durationAlert(
        title: String,
        message: String,
        goalPlaceholder: String?,
        style: NSAlert.Style = .informational,
        icon: String? = nil,
        prefix: [String] = [],
        presets: [(String, Int)],
        customButtonTitle: String? = nil,
        extras: [String] = []
    ) -> (choice: DurationChoice, goal: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        if let icon {
            alert.icon = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        alert.messageText = title
        alert.informativeText = message

        let goalField: NSTextField? = goalPlaceholder.map { placeholder in
            let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            f.placeholderString = placeholder
            return f
        }
        var minutesField: NSTextField?
        var confirmButton: NSButton?
        if customButtonTitle != nil {
            // Goal (optional) on top, then a "自定义 [ ] 分钟 [确定]" row below.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            var y: CGFloat = 0
            if let goalField {
                goalField.frame.origin.y = y
                container.addSubview(goalField)
                y += 30
            }
            let label = NSTextField(labelWithString: "自定义")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y + 1, width: 52, height: 22)
            container.addSubview(label)
            minutesField = NSTextField(frame: NSRect(x: 56, y: y, width: 40, height: 24))
            minutesField?.alignment = .right
            container.addSubview(minutesField!)
            let unitLabel = NSTextField(labelWithString: "分钟")
            unitLabel.font = .systemFont(ofSize: 12)
            unitLabel.textColor = .secondaryLabelColor
            unitLabel.frame = NSRect(x: 100, y: y + 1, width: 40, height: 22)
            container.addSubview(unitLabel)
            confirmButton = NSButton(title: "确定", target: nil, action: nil)
            confirmButton?.controlSize = .small
            confirmButton?.font = .systemFont(ofSize: 11)
            confirmButton?.frame = NSRect(x: 144, y: y, width: 44, height: 22)
            container.addSubview(confirmButton!)
            y += 30
            container.frame.size.height = y
            alert.accessoryView = container
        } else if let goalField {
            goalField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = goalField
        }

        var buttons: [String] = prefix
        buttons += presets.map { $0.0 }
        if let customButtonTitle { buttons.append(customButtonTitle) }
        buttons += extras
        buttons.forEach { alert.addButton(withTitle: $0) }

        // The custom entry is confirmed via the 确定 button or by pressing Return
        // inside the minutes field — both click a hidden "自定义" button so runModal
        // reports the custom choice.
        if let minutesField, customButtonTitle != nil {
            let customIndex = prefix.count + presets.count
            if customIndex < alert.buttons.count {
                let customButton = alert.buttons[customIndex]
                customButton.isHidden = true
                minutesField.target = customButton
                minutesField.action = #selector(NSButton.performClick(_:))
                confirmButton?.target = customButton
                confirmButton?.action = #selector(NSButton.performClick(_:))
            }
        }

        // Focus the first input (goal, else minutes) once the modal window exists,
        // so the blinking caret is visible without needing a click.
        if let initialField = goalField ?? minutesField {
            let focusTimer = Timer(timeInterval: 0.1, repeats: false) { [weak alert] _ in
                MainActor.assumeIsolated {
                    _ = alert?.window.makeFirstResponder(initialField)
                }
            }
            RunLoop.main.add(focusTimer, forMode: .modalPanel)
        }

        let idx = Int(alert.runModal().rawValue) - 1000
        let goal = goalField?.stringValue ?? ""
        let customMinutes = minutesField.map {
            Int($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } ?? 0

        let p = prefix.count
        let c = presets.count
        let customOffset = customButtonTitle == nil ? 0 : 1
        let choice: DurationChoice
        if idx < p {
            choice = .prefix(idx)
        } else if idx < p + c {
            choice = .preset(idx - p)
        } else if customButtonTitle != nil && idx == p + c {
            choice = .custom(minutes: customMinutes)
        } else {
            choice = .extra(idx - p - c - customOffset)
        }
        return (choice, goal)
    }

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
    }

    private func presentFocusEndReminder() {
        guard !focusEndReminderInFlight else { return }
        focusEndReminderInFlight = true
        defer { focusEndReminderInFlight = false }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "专注计时已结束",
            icon: "timer",
            section1Title: "专注计时",
            message: "要开始下一段专注计时吗？休息一下，别忘了回来继续。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            secondaryTitle: "稍后提醒"
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .pause:
            openPractice(.breathing)
        default:
            break                           // 稍后提醒 → 循环继续，间隔后再次提醒
        }
    }

    private func presentFocusTimerReminder() {
        guard remindFocusTimerAfterBlock else { return }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "屏蔽已开启",
            icon: "lock.open",
            section1Title: "专注计时",
            message: "要开始专注计时吗？计时中屏蔽名单会锁定。可填一个目标，计时中悬浮提醒。",
            presets: [("25 分钟", 25), ("30 分钟", 30), ("60 分钟", 60)],
            showGoal: true,
            goalPlaceholder: "这次想专注完成什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            secondaryTitle: "取消"
        ))
        switch result.choice {
        case .preset(let minutes):
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startFocusTimer(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .pause:
            openPractice(.breathing)
        default:
            break
        }
    }

    private func presentDelayedBlockReminder() {
        guard remindDelayedBlockAfterUnblock else { return }
        guard !focusTimerActive else { return }
        let result = PromptPanelPresenter.run(PromptPanelConfig(
            title: "屏蔽已停止",
            icon: "clock",
            section1Title: "延时屏蔽",
            message: "要设置延时屏蔽吗？到点自动重新屏蔽。可填这段时间想做什么，悬浮提醒。",
            presets: [("5 分钟", 5), ("10 分钟", 10), ("30 分钟", 30)],
            showGoal: true,
            goalPlaceholder: "这段时间想做什么？",
            actionItems: actionPrompts,
            textItems: textPrompts,
            primaryTitle: "开始",
            secondaryTitle: "取消"
        ))
        switch result.choice {
        case .preset(let minutes):
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom(let minutes) where minutes > 0:
            startDelayedBlock(minutes: minutes, goal: result.goal)
        case .custom:
            lastError = "请输入有效的自定义分钟数"
        case .pause:
            openPractice(.breathing)
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
        UserDefaults.standard.set(data, forKey: "prompts")
    }

    private func loadPrompts() {
        if let data = UserDefaults.standard.data(forKey: "prompts"),
           let saved = try? JSONDecoder().decode([PromptItem].self, from: data),
           !saved.isEmpty {
            prompts = saved
            return
        }
        // 迁移上一版「鼓励语」卡片，保留用户已写文案。
        if let data = UserDefaults.standard.data(forKey: "encouragementCards"),
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
        UserDefaults.standard.set(data, forKey: "toolboxGroups")
    }

    private func loadToolboxLinks() {
        if let data = UserDefaults.standard.data(forKey: "toolboxGroups"),
           let saved = try? JSONDecoder().decode([ToolboxGroup].self, from: data),
           !saved.isEmpty {
            var groups = saved
            // 合并旧扁平数据里缺失的链接（幂等：按 id 或 标题|地址 判重，只补缺失项）
            if let flatData = UserDefaults.standard.data(forKey: "toolboxLinks"),
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
        if let data = UserDefaults.standard.data(forKey: "toolboxLinks"),
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
