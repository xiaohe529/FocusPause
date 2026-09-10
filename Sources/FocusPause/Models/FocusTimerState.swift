import Foundation

struct FocusTimerState: Codable {
    enum Kind: String, Codable { case focus, delayedBlock, scheduledBlock }
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
    /// 定时屏蔽「紧急退出」每月已用次数（与专注计时额度互相独立，随 lastResetMonth 重置）。
    var scheduledExitUsesThisMonth: Int? = nil
    /// 正计时的开始时刻（无 endTimestamp 时表示正在向上计时）。
    var focusTimerStart: Date? = nil
    /// 普通倒计时专注的开始时刻，用于进度显示；旧状态可为空。
    var focusCountdownStart: Date? = nil
}
