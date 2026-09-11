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
