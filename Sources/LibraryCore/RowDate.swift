import Foundation

/// The date a file list row shows: the time for today, "Yesterday", otherwise the system short date.
/// Holds its formatters, so keep one around instead of making one per row.
public final class RowDateFormatter {
    private let calendar: Calendar
    private let time = DateFormatter()
    private let day = DateFormatter()

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        for formatter in [time, day] {
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
        }
        time.dateStyle = .none
        time.timeStyle = .short
        day.dateStyle = .short
        day.timeStyle = .none
    }

    public func label(for date: Date, now: Date = Date()) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return day.string(from: date)
    }
}
