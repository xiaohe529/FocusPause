import Foundation

/// A typed facade over UserDefaults. AppState and app views should use this
/// instead of scattering string keys across the codebase.
struct AppSettingsStore {
    enum Key: String, CaseIterable {
        case ignoredUpdateVersion
        case emergencyQuota
        case emergencyQuotaSetMonth
        case scheduledExitQuota
        case scheduledExitQuotaSetMonth
        case launchAtLogin
        case blockingEnabled
        case forceBlockAll
        case delayedBlockLockScreen
        case delayedBlockAllowExtension
        case focusOverlayShowsTime
        case reminderEnabled
        case reminderIntervalMinutes
        case remindBlockingNoFocus
        case blockingNoFocusIntervalMinutes
        case coolingEnabled
        case coolingMinutes
        case remindFocusTimerAfterBlock
        case remindDelayedBlockAfterUnblock
        case remindFocusTimerAfterEnd
        case remindCountdownManualEnd
        case remindRestManualEnd
        case breakGlassEnabled
        case didMigrateLegacyDefaults
        case scheduledWindows
        case scheduledReleasedOccurrenceKey
        case prompts
        case encouragementCards
        case toolboxGroups
        case toolboxLinks
        case minimizeHintSuppressed
    }

    nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let standard = AppSettingsStore()

    func object(_ key: Key) -> Any? {
        defaults.object(forKey: key.rawValue)
    }

    func bool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        object(key) as? Bool ?? defaultValue
    }

    func optionalBool(_ key: Key) -> Bool? {
        object(key) as? Bool
    }

    func int(_ key: Key, default defaultValue: Int = 0) -> Int {
        object(key) as? Int ?? defaultValue
    }

    func optionalInt(_ key: Key) -> Int? {
        object(key) as? Int
    }

    func string(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    func data(_ key: Key) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    func set(_ value: Any?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func remove(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
