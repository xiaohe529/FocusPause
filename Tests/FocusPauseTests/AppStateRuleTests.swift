import Foundation
import Testing
@testable import FocusPause

@MainActor
struct AppStateRuleTests {
    @Test
    func effectiveRulesRespectEnabledAndForceAll() {
        let appState = AppState()
        appState.blockRules = [
            BlockRule(name: "example.com", type: .website, enabled: true),
            BlockRule(name: "disabled.com", type: .website, enabled: false),
            BlockRule(name: "invalid website", type: .website, enabled: true),
            BlockRule(name: "Video", type: .app, enabled: true),
            BlockRule(name: "Disabled App", type: .app, enabled: false)
        ]
        appState.forceBlockAll = false

        #expect(appState.effectiveWebsites == ["example.com"])
        #expect(appState.effectiveApps == ["Video"])
        #expect(appState.invalidWebsiteRules.map(\.name) == ["invalid website"])

        appState.forceBlockAll = true
        #expect(appState.effectiveWebsites == ["example.com", "disabled.com"])
        #expect(appState.effectiveApps == ["Video", "Disabled App"])
    }

    @Test
    func ruleListIsLockedDuringBlockingOrTimer() {
        let appState = AppState()
        #expect(appState.ruleListLockedError() == nil)

        appState.blockingEnabled = true
        #expect(appState.ruleListLockedError()?.contains("屏蔽开启中") == true)

        appState.blockingEnabled = false
        appState.focusTimerActive = true
        #expect(appState.ruleListLockedError()?.contains("专注计时中") == true)

        appState.focusTimerActive = false
        appState.restActive = true
        #expect(appState.ruleListLockedError()?.contains("休息中") == true)
    }

    @Test
    func breakGlassUnlocksOnlyAfterTheRegularEmergencyQuotaIsExhausted() {
        let appState = AppState()
        appState.breakGlassEnabled = false
        appState.focusTimerActive = false
        appState.blockingEnabled = false

        // 空闲时没有硬锁可解，应给出「用不到」的说明而不是直接放行。
        #expect(appState.breakGlassUnlockBlockedReason() != nil)

        // 专注计时中，常规额度还有剩 → 必须先走常规紧急退出。
        appState.emergencyQuota = 3
        appState.emergencyUsesThisMonth = 1
        appState.focusTimerActive = true
        #expect(appState.breakGlassUnlockBlockedReason()?.contains("还有 2 次") == true)
        #expect(!appState.canStartBreakGlassUnlock())

        // 常规额度用尽 → 解锁条件成立，即使特性此前未启用也能直接解锁。
        appState.emergencyUsesThisMonth = appState.emergencyQuota
        #expect(appState.breakGlassUnlockBlockedReason() == nil)
        #expect(appState.canStartBreakGlassUnlock())
    }

    @Test
    func breakGlassUnlockIsBlockedOnceUsedToday() {
        let appState = AppState()
        appState.focusTimerActive = true
        appState.emergencyQuota = 1
        appState.emergencyUsesThisMonth = 1

        #expect(appState.breakGlassUnlockBlockedReason() == nil)

        // 今天已经发起过一次 → 再点解锁必须被拒绝，并说明是「今日已用完」。
        let today = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        appState.breakGlassLastAttemptDay = today

        #expect(appState.breakGlassUnlockBlockedReason()?.contains("今日") == true)
        #expect(!appState.canStartBreakGlassUnlock())
    }

    /// 回归测试：`breakGlassCooldownEnd` 在冷静期自然走完后**不会**被清空
    /// （只有放弃 / 完成才清空）。所以「冷静期进行中」必须按时间判断，
    /// 否则倒计时结束后仍会显示「冷静期进行中」，并和「确认解除所有屏蔽」按钮同时出现。
    @Test
    func breakGlassCooldownExpiryReportsConfirmStepNotInProgress() {
        let appState = AppState()
        appState.focusTimerActive = true
        appState.emergencyQuota = 1
        appState.emergencyUsesThisMonth = 1

        let now = Date()

        // 冷静期还剩 1 分钟 → 提示「进行中」。
        appState.breakGlassCooldownEnd = now.addingTimeInterval(60)
        #expect(appState.breakGlassUnlockBlockedReason(at: now)?.contains("冷静期进行中") == true)
        #expect(!appState.isBreakGlassReadyToComplete(at: now))

        // 冷静期已过期但未确认 → 不能再报「进行中」，也不能误报「今日次数已用完」。
        appState.breakGlassCooldownEnd = now.addingTimeInterval(-1)
        let reason = appState.breakGlassUnlockBlockedReason(at: now)
        #expect(reason?.contains("冷静期进行中") == false)
        #expect(reason?.contains("今日") == false)
        #expect(reason?.contains("确认解除所有屏蔽") == true)
        #expect(appState.isBreakGlassReadyToComplete(at: now))
    }
}

/// 回归测试：写盘的 (kind, endTimestamp) 必须来自同一来源。
/// 曾经的实现用 `focusTimerActive ? focusTimerEnd : delayedBlockEnd` 取值，
/// 在定时屏蔽（kind = .scheduledBlock、focusTimerActive = false）时会写出一个
/// 「有 kind、但 end 来自错误的计时器」的半截状态。
@MainActor
struct AppStateTimerPersistenceTests {
    @Test
    func countdownFocusPersistsFocusKindWithItsOwnEnd() {
        let appState = AppState()
        let end = Date().addingTimeInterval(600)
        appState.focusTimerActive = true
        appState.focusTimerEnd = end

        let snapshot = appState.persistedTimerKindAndEnd
        #expect(snapshot.kind == .focus)
        #expect(snapshot.end == end)
    }

    @Test
    func delayedBlockPersistsDelayedKindWithItsOwnEnd() {
        let appState = AppState()
        let end = Date().addingTimeInterval(300)
        appState.delayedBlockActive = true
        appState.delayedBlockEnd = end
        // 同时存在一个已结束的专注计时，验证不会串用 focusTimerEnd。
        appState.focusTimerActive = true
        appState.focusTimerEnd = Date().addingTimeInterval(9999)

        let snapshot = appState.persistedTimerKindAndEnd
        #expect(snapshot.kind == .focus)
        #expect(snapshot.end == appState.focusTimerEnd)
    }

    @Test
    func scheduledBlockNeverBorrowsAnotherTimersEnd() {
        let appState = AppState()
        // enabled 必须为 true，且窗口要覆盖当前时刻（当天 00:00–23:59）。
        let calendar = Calendar.current
        let now = Date()
        let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let window = minuteOfDay < 23 * 60
            ? ScheduledWindow(id: UUID(), startMinute: 0, endMinute: 23 * 60 + 59, enabled: true)
            : ScheduledWindow(id: UUID(), startMinute: 0, endMinute: 0, enabled: true)  // 跨夜
        appState.scheduledWindows = [window]
        #expect(appState.isScheduledLockActive)

        let snapshot = appState.persistedTimerKindAndEnd
        #expect(snapshot.kind == .scheduledBlock)
        #expect(snapshot.end == nil, "定时屏蔽不占用 endTimestamp，否则会写出半截状态")
    }

    @Test
    func idleStatePersistsNoKindAndNoEnd() {
        let appState = AppState()
        let snapshot = appState.persistedTimerKindAndEnd
        #expect(snapshot.kind == nil)
        #expect(snapshot.end == nil)
    }
}

/// 「未屏蔽提醒」循环的触发条件。长睡前后必须是同一组条件——旧实现第二次
/// 检查漏了 delayedBlockPendingAuth，会在「屏蔽未生效」的重试弹窗期间抢弹窗。
@MainActor
struct AppStateReminderLoopConditionTests {
    @Test
    func pendingAuthBlocksTheReminderRegardlessOfWhenChecked() {
        let appState = AppState()
        appState.reminderEnabled = true

        appState.delayedBlockPendingAuth = true
        #expect(!appState.reminderLoopShouldRun, "授权待重试期间不得弹出未屏蔽提醒")
    }

    @Test
    func blockingNoFocusLoopYieldsWhileAnotherReminderIsUp() {
        let appState = AppState()
        appState.remindBlockingNoFocus = true
        appState.blockingEnabled = true
        #expect(appState.blockingNoFocusLoopShouldRun)

        // 另一个提醒弹窗正在显示时必须让位，否则上一个刚关、下一个紧接着弹，
        // 两个模态叠在一起 → 主线程卡在嵌套 runModal，界面彻底卡死。
        appState.setReminderModalInFlightForTesting(true)
        #expect(!appState.blockingNoFocusLoopShouldRun,
                "已有提醒弹窗在显示时，「已屏蔽未专注」不得再弹")

        appState.setReminderModalInFlightForTesting(false)
        #expect(appState.blockingNoFocusLoopShouldRun)
    }
}
