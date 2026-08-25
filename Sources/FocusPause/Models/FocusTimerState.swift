import Foundation

struct FocusTimerState: Codable {
    enum Kind: String, Codable { case focus, delayedBlock }
    var kind: Kind?
    var endTimestamp: Date?
    var emergencyUsesThisMonth: Int
    var lastResetMonth: String
    var delayedBlockPendingAuth: Bool?
    var delayedBlockRetryCount: Int?
    /// The goal/plan the user set for this delayed-block session, shown in a floating
    /// always-on-top overlay during the countdown to keep them on task.
    var delayedBlockGoal: String?
    /// The goal the user set for this focus session, shown in the same floating overlay.
    var focusTimerGoal: String?
}
