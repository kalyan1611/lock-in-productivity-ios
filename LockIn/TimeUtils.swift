import SwiftUI

// MARK: - Time Utilities

enum TimeUtils {
    
    private static let freeStartHour = 8
    private static let freeEndHour = 23

    static func isFreeTime(for date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sun ... 7 = Sat
        let hour = calendar.component(.hour, from: date)

        switch weekday {
        case 7: // Saturday — fully inside the weekend window, always free
            return true
        case 6: // Friday — normal open, then rolls straight into the weekend
            return hour >= freeStartHour
        case 1: // Sunday — weekend window continues until freeEndHour
            return hour < freeEndHour
        default: // Monday - Thursday: standard daily window
            return hour >= freeStartHour && hour < freeEndHour
        }
    }

    /// The next moment `isFreeTime` will become true again. Returns nil if
    /// we're already in free time.
    ///
    /// Every "not free" moment is either before today's freeStartHour, or
    /// at/after today's freeEndHour — the weekend window never leaves a
    /// "not free" gap of its own (Sat/Sun mornings and Fri evenings are
    /// already free), so both branches below can safely assume they're
    /// dealing with an ordinary Mon-Fri lockout.
    static func nextFreeTime(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !isFreeTime(for: date, calendar: calendar) else { return nil }

        let currentHour = calendar.component(.hour, from: date)

        if currentHour < freeStartHour {
            // Before the window opens today — resumes later today.
            return calendar.date(bySettingHour: freeStartHour, minute: 0, second: 0, of: date)
        }

        // At or past today's close. This can only happen on Sun (after 11
        // PM, once the weekend window has ended) or Mon-Thu nights — Fri
        // nights are always inside the weekend window and caught by the
        // guard above. Either way, tomorrow's normal reopen is freeStartHour:
        // Monday is a plain weekday, and if tomorrow were Friday its normal
        // open is still freeStartHour (the weekend window doesn't start
        // until 6 PM Friday).
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return calendar.date(bySettingHour: freeStartHour, minute: 0, second: 0, of: calendar.startOfDay(for: tomorrow))
    }

    /// Label for the lockout banner: "LOCKED UNTIL 8:00 AM" if the window
    /// reopens later today, or "LOCKED UNTIL TOMORROW 8:00 AM" if it spans
    /// to the next day.
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
