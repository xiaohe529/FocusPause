import Foundation

/// 定时屏蔽的一条时间段。
/// - `repeats == true`：每天重复（只用当日时间 startMinute/endMinute）。
/// - `repeats == false`：一次性（结合 anchorDay 的日期 + 当日时间），所带期间结束后自动移除。
struct ScheduledWindow: Codable, Identifiable, Equatable {
    var id: UUID
    /// true=每天重复；false=一次性。
    var repeats: Bool = true
    /// 开始时刻（分钟，0–1439）。
    var startMinute: Int
    /// 结束时刻（分钟，0–1439）。endMinute < startMinute 表示跨到次日，如 22:00–02:00。
    var endMinute: Int
    /// 一次性时间段所属的日期（该日零点）；每天重复时为 nil。
    var anchorDay: Date? = nil
    /// 是否已手动「生效」。仅生效的时间段才会触发屏蔽；新加的时间段默认关，避免设置时误屏蔽。
    var enabled: Bool = false
}