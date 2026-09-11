import Foundation
import Testing
@testable import FocusPause

struct AppSettingsStoreTests {
    private func temporaryStore() throws -> (AppSettingsStore, UserDefaults) {
        let name = "FocusPauseTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (AppSettingsStore(defaults: defaults), defaults)
    }

    @Test
    func typedKeysRoundTrip() throws {
        let (settings, _) = try temporaryStore()
        settings.set("1.2.3", for: .ignoredUpdateVersion)
        settings.set(true, for: .reminderEnabled)
        settings.set(45, for: .reminderIntervalMinutes)

        #expect(settings.string(.ignoredUpdateVersion) == "1.2.3")
        #expect(settings.bool(.reminderEnabled))
        #expect(settings.int(.reminderIntervalMinutes) == 45)
    }

    @Test
    func optionalValuesUseDefaultsAndClearing() throws {
        let (settings, _) = try temporaryStore()
        #expect(settings.optionalBool(.delayedBlockAllowExtension) == nil)
        #expect(settings.bool(.delayedBlockAllowExtension, default: true))
        #expect(settings.optionalInt(.emergencyQuota) == nil)
        #expect(settings.int(.emergencyQuota, default: 3) == 3)

        settings.set(false, for: .delayedBlockAllowExtension)
        #expect(settings.optionalBool(.delayedBlockAllowExtension) == false)

        settings.remove(.delayedBlockAllowExtension)
        #expect(settings.optionalBool(.delayedBlockAllowExtension) == nil)
    }
}
