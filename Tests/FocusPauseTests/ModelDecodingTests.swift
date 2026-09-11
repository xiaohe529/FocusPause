import Foundation
import Testing
@testable import FocusPause

struct ModelDecodingTests {
    @Test
    func blockRuleCodableRoundTrip() throws {
        let rule = BlockRule(name: "Video", type: .app, enabled: false)
        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([BlockRule].self, from: data)
        #expect(decoded == [rule])
    }

    @Test
    func focusTimerStateBackwardCompatibleFields() throws {
        let json = """
        {"kind":"delayedBlock","endTimestamp":1780000000,"emergencyUsesThisMonth":1,"lastResetMonth":"2026-09"}
        """
        let state = try JSONDecoder().decode(FocusTimerState.self, from: Data(json.utf8))
        #expect(state.kind == .delayedBlock)
        #expect(state.emergencyUsesThisMonth == 1)
        #expect(state.scheduledExitUsesThisMonth == nil)
        #expect(state.restMinutes == nil)
    }
}
