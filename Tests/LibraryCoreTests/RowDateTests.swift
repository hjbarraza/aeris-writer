import Testing
import Foundation
@testable import LibraryCore

struct RowDateTests {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let formatter = RowDateFormatter(calendar: calendar, locale: Locale(identifier: "en_US"))
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 14, minute: 30))!

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    @Test func todayShowsTime() { #expect(formatter.label(for: at(15, 9, 5), now: now) == "9:05\u{202F}AM") }
    @Test func yesterday() {
        #expect(formatter.label(for: at(14, 23, 59), now: now) == "Yesterday")
        #expect(formatter.label(for: at(14, 0, 0), now: now) == "Yesterday")
    }
    @Test func olderAndFutureShowShortDate() {
        #expect(formatter.label(for: at(13, 12), now: now) == "3/13/26")
        #expect(formatter.label(for: at(16, 12), now: now) == "3/16/26")
    }
}
