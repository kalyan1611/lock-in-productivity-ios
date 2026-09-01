import SwiftUI

// MARK: - Time Utilities

enum TimeUtils {
    private static let freeStartHour = 8
    private static let freeEndHour = 23

    static func isFreeTime(for date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = (weekday == 1 || weekday == 7) // 1 = Sunday, 7 = Saturday

        if isWeekend {
            return true
        }

        let currentHour = calendar.component(.hour, from: date)
        return currentHour >= freeStartHour && currentHour < freeEndHour
    }

    /// The next moment `isFreeTime` will become true again. Returns nil if
    /// we're already in free time (weekends are always free; weekdays are
    /// free 8 AM–11 PM).
    static func nextFreeTime(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !isFreeTime(for: date, calendar: calendar) else { return nil }

        let currentHour = calendar.component(.hour, from: date)

        if currentHour < freeStartHour {
            // Before the window opens today — resumes later today.
            return calendar.date(bySettingHour: freeStartHour, minute: 0, second: 0, of: date)
        }

        // At or past the window close — resumes either at midnight (if
        // tomorrow is a weekend) or freeStartHour tomorrow (if a weekday).
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        let tomorrowWeekday = calendar.component(.weekday, from: tomorrow)
        let tomorrowIsWeekend = (tomorrowWeekday == 1 || tomorrowWeekday == 7)
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)

        return tomorrowIsWeekend
            ? startOfTomorrow
            : calendar.date(bySettingHour: freeStartHour, minute: 0, second: 0, of: startOfTomorrow)
    }

    /// Label for the lockout banner: "LOCKED UNTIL 8:00 AM" if the window
    /// reopens later today, or "LOCKED UNTIL TOMORROW 8:00 AM" if it spans
    /// to the next day. Never further out than that — weekday lockouts max
    /// out at one day, since weekends are always free time.
    static func lockoutLabel(from date: Date = Date(), calendar: Calendar = .current) -> String {
        guard let next = nextFreeTime(from: date, calendar: calendar) else {
            return "RESTRICTED"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: next)

        return calendar.isDate(next, inSameDayAs: date)
            ? "LOCKED UNTIL \(timeString)"
            : "LOCKED UNTIL TOMORROW \(timeString)"
    }
}
