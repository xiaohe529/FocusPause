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
extension ScheduledWindow {
    /// Stable key for one run of this window on `day` (the start day; overnight
    /// windows that are active after midnight use the previous day).
    func occurrenceKey(day: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(id.uuidString)|\(formatter.string(from: day))"
    }

    /// Returns the occurrence key while `now` is inside this window, or nil.
    func activeKey(now: Date, calendar: Calendar) -> String? {
        if repeats {
            return activeKeyForDaily(now: now, calendar: calendar)
        }
        return activeKeyForOneTime(now: now, calendar: calendar)
    }

    private func activeKeyForDaily(now: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let overnight = endMinute < startMinute

        if !overnight {
            guard minute >= startMinute && minute < endMinute else { return nil }
            return occurrenceKey(day: calendar.startOfDay(for: now), calendar: calendar)
        }
        if minute >= startMinute {
            return occurrenceKey(day: calendar.startOfDay(for: now), calendar: calendar)
        }
        guard minute < endMinute else { return nil }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        return occurrenceKey(day: yesterday, calendar: calendar)
    }

    private func activeKeyForOneTime(now: Date, calendar: Calendar) -> String? {
        guard let anchorDay else { return nil }
        let startDay = calendar.startOfDay(for: anchorDay)
        let start = startDay.addingTimeInterval(TimeInterval(startMinute * 60))
        let spanMinutes = endMinute > startMinute
            ? endMinute - startMinute
            : 24 * 60 + endMinute - startMinute
        let end = start.addingTimeInterval(TimeInterval(spanMinutes * 60))
        guard now >= start && now < end else { return nil }
        return occurrenceKey(day: startDay, calendar: calendar)
    }
}
