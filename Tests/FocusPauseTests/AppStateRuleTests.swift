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
    func breakGlassCanBeConfiguredWhenIdleOrDuringExhaustedHardLock() {
        let appState = AppState()
        appState.breakGlassEnabled = false

        #expect(appState.canConfigureBreakGlass)
        #expect(!appState.canEnableBreakGlassDuringLock)

        appState.focusTimerActive = true
        appState.emergencyUsesThisMonth = appState.emergencyQuota
        #expect(!appState.canConfigureBreakGlass)
        #expect(appState.canEnableBreakGlassDuringLock)
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
