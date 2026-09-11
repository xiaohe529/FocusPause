import Foundation
import Testing
@testable import FocusPause

struct ScheduledWindowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test
    func dailyWindowIsHalfOpen() throws {
        let window = ScheduledWindow(id: UUID(), repeats: true, startMinute: 9 * 60, endMinute: 10 * 60, enabled: true)
        let key = try #require(window.activeKey(now: date(2026, 9, 11, 9, 0), calendar: calendar))
        #expect(key.hasPrefix(window.id.uuidString))
        #expect(key.hasSuffix("|2026-09-11"))
        #expect(window.activeKey(now: date(2026, 9, 11, 10, 0), calendar: calendar) == nil)
    }

    @Test
    func overnightDailyWindowAfterMidnightBelongsToPreviousDay() throws {
        let window = ScheduledWindow(id: UUID(), repeats: true, startMinute: 22 * 60, endMinute: 2 * 60, enabled: true)
        let key = try #require(window.activeKey(now: date(2026, 9, 12, 1, 59), calendar: calendar))
        #expect(key.hasSuffix("|2026-09-11"))
        #expect(window.activeKey(now: date(2026, 9, 12, 2, 0), calendar: calendar) == nil)
    }

    @Test
    func oneTimeWindowRequiresAnchorAndRespectsSpan() throws {
        let id = UUID()
        let anchor = date(2026, 9, 10, 0, 0)
        let window = ScheduledWindow(id: id, repeats: false, startMinute: 23 * 60, endMinute: 1 * 60, anchorDay: anchor, enabled: true)
        let key = try #require(window.activeKey(now: date(2026, 9, 11, 0, 30), calendar: calendar))
        #expect(key.hasPrefix(id.uuidString))
        #expect(window.activeKey(now: date(2026, 9, 11, 1, 0), calendar: calendar) == nil)

        var missingAnchor = window
        missingAnchor.anchorDay = nil
        #expect(missingAnchor.activeKey(now: date(2026, 9, 10, 23, 30), calendar: calendar) == nil)
    }
}
