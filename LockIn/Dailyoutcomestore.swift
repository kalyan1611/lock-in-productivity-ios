import Foundation

// MARK: - Daily Outcome Store

/// One of three states a single goal lands in for a single calendar day.
/// Persisted per goal per day so a later "last week" retrospective can
/// distinguish "hit it for real" from "used a waive-off" from "missed it"
/// — a distinction that's otherwise lost by end of day: the ESP32 only
/// tracks the *current* waived date per goal (overwritten, no history),
/// and NetworkManager's waive-off cache explicitly zeroes out the waived
/// flags once the cache is from a prior day.
enum GoalOutcome: String, Codable {
    case met
    case waived
    case missed
}

/// Keychain-backed log of each goal's daily outcome, one entry per goal
/// per calendar day. Like GymTracker's / LeetCodeManager's history
/// caches, this only starts accumulating from whenever it first ships —
/// there's no way to reconstruct outcomes for days before that, since the
/// waive-off info in particular is already gone by the next day.
///
/// An entry for a given date is only ever written while that date is
/// "today" — `recordOutcome` is meant to be called once per successful
/// sync, and each call freely overwrites *today's* entry as the day's
/// live data changes (e.g. solving a LeetCode problem later in the day
/// flips that goal from "missed" to "met"). Once the calendar date
/// advances, nothing ever writes to the previous day's key again, so a
/// past day's entry is permanently frozen at whatever it was when the
/// day ended — which is exactly the "closed week" semantics a
/// retrospective needs.
enum DailyOutcomeStore {
    enum Goal: String {
        case steps
        case gym
        case leetcode
    }

    private static let keyPrefix = "LockIn_DailyOutcome_"
    private static let trackingStartDateKey = keyPrefix + "TrackingStartDate"

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private static func key(_ goal: Goal, _ date: Date) -> String {
        keyPrefix + goal.rawValue + "_" + dateString(date)
    }

    /// The date of the very first `recordOutcome` call ever made, written
    /// once and never touched again after that. This is what lets
    /// `outcome(goal:date:)` tell "a day nothing was synced on" apart from
    /// "a day from before this feature even existed" — only the former
    /// should read as a missed day.
    private static var trackingStartDate: Date? {
        KeychainStore.string(forKey: trackingStartDateKey).flatMap(date(from:))
    }

    private static func markTrackingStartedIfNeeded(on recordedDate: Date) {
        guard KeychainStore.string(forKey: trackingStartDateKey) == nil else { return }
        KeychainStore.setString(dateString(recordedDate), forKey: trackingStartDateKey)
    }

    /// Call once per successful sync with that goal's current live state.
    /// Safe to call repeatedly through the day — always overwrites
    /// today's entry with the latest outcome, never touches any other
    /// date. `metGoal` wins over `waivedToday` if somehow both are true,
    /// matching the same "actually meeting it outranks skipping it"
    /// precedence used elsewhere (see GoalColor.forProgress).
    static func recordOutcome(
        goal: Goal,
        metGoal: Bool,
        waivedToday: Bool,
        date: Date = Date()
    ) {
        markTrackingStartedIfNeeded(on: date)
        let outcome: GoalOutcome = metGoal ? .met : (waivedToday ? .waived : .missed)
        KeychainStore.setString(outcome.rawValue, forKey: key(goal, date))
    }

    /// Reads back whatever was recorded for that goal/date, with one
    /// fallback: if there's no explicit entry, a day that's already fully
    /// passed *and* falls on or after `trackingStartDate` is treated as
    /// `.missed` — no sync that day means the goal didn't get done, same
    /// as if it had been explicitly logged as missed. This only applies
    /// once tracking has actually started; a day from before this feature
    /// shipped has no way to have been synced against, so it stays `nil`
    /// rather than silently reading as a wall of missed days. Today itself
    /// also stays `nil` until it actually ends — it hasn't been judged yet.
    static func outcome(
        goal: Goal,
        date: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalOutcome? {
        if let raw = KeychainStore.string(forKey: key(goal, date)), let recorded = GoalOutcome(rawValue: raw) {
            return recorded
        }

        guard let trackingStartDate else { return nil }
        let today = calendar.startOfDay(for: referenceDate)
        let queriedDay = calendar.startOfDay(for: date)
        guard queriedDay >= calendar.startOfDay(for: trackingStartDate), queriedDay < today else {
            return nil
        }
        return .missed
    }

    /// Convenience for the retrospective card: every goal's outcome for
    /// one calendar day, keyed by `Goal`. A goal reads `nil` only if that
    /// day is today (not over yet) or predates `trackingStartDate` —
    /// otherwise a day with no explicit entry resolves to `.missed` (see
    /// `outcome(goal:date:)`).
    static func outcomes(for date: Date) -> [Goal: GoalOutcome?] {
        Dictionary(uniqueKeysWithValues: [Goal.steps, .gym, .leetcode].map { goal in
            (goal, outcome(goal: goal, date: date))
        })
    }

    /// True only if all three goals for that date resolved to `.met` —
    /// mirrors the firmware's `goalsFullyMet()` semantics (waive-offs
    /// unlock the day but don't count as "fully met" here), so a
    /// retrospective's day-level rollup stays consistent with how the
    /// gate itself decided things that day.
    static func allGoalsMet(for date: Date) -> Bool {
        [Goal.steps, .gym, .leetcode].allSatisfy { outcome(goal: $0, date: date) == .met }
    }

    // MARK: - Last Completed Week / Month

    struct GoalPeriodSummary {
        let metCount: Int
        let waivedCount: Int
        /// 7 for a week, 28-31 for a calendar month — the denominator the
        /// caller should display "metCount / totalDays" against.
        let totalDays: Int
        /// True only once *every* day in the period has a real recorded
        /// outcome — not just some of them. A period where logging only
        /// covered part of it (e.g. it started mid-month) stays false
        /// rather than showing a misleadingly low fraction against the
        /// full period length; it'll start reporting once a full period
        /// falls entirely after logging began.
        let hasData: Bool
    }

    /// `metCount`/`waivedCount` (out of 7) for one goal over the most
    /// recently *completed* Mon-Sun week — never the current, in-progress
    /// week, since a partial week isn't comparable to a full one and
    /// today's live state is already shown elsewhere in the app.
    ///
    /// Week boundary mirrors dns_filter's `getMondayDateString()` exactly
    /// (tm_wday 0 = Sun ... 6 = Sat, daysSinceMonday = wday == 0 ? 6 :
    /// wday - 1), so "last week" here means the same calendar week the
    /// ESP32 resets waive-offs on. Calendar's `weekday` is tm_wday + 1, so
    /// the same rule becomes `weekday - 2`, with Sunday (weekday == 1)
    /// special-cased to 6.
    static func lastWeekSummary(
        for goal: Goal,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalPeriodSummary {
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2

        guard let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today),
              let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)
        else {
            return GoalPeriodSummary(metCount: 0, waivedCount: 0, totalDays: 7, hasData: false)
        }

        let outcomes: [GoalOutcome?] = (0 ..< 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: lastMonday) else { return nil }
            return outcome(goal: goal, date: date)
        }

        return GoalPeriodSummary(
            metCount: outcomes.filter { $0 == .met }.count,
            waivedCount: outcomes.filter { $0 == .waived }.count,
            totalDays: 7,
            hasData: outcomes.count == 7 && outcomes.allSatisfy { $0 != nil }
        )
    }

    /// Same idea as `lastWeekSummary`, but for the most recently completed
    /// *calendar* month (1st through last day of the previous month) —
    /// never the current, in-progress month. `totalDays` varies with the
    /// month (28-31), unlike the week version's fixed 7.
    static func lastMonthSummary(
        for goal: Goal,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalPeriodSummary {
        let today = calendar.startOfDay(for: referenceDate)

        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth),
              let daysInMonth = calendar.range(of: .day, in: .month, for: startOfLastMonth)?.count
        else {
            return GoalPeriodSummary(metCount: 0, waivedCount: 0, totalDays: 0, hasData: false)
        }

        let outcomes: [GoalOutcome?] = (0 ..< daysInMonth).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfLastMonth) else { return nil }
            return outcome(goal: goal, date: date)
        }

        return GoalPeriodSummary(
            metCount: outcomes.filter { $0 == .met }.count,
            waivedCount: outcomes.filter { $0 == .waived }.count,
            totalDays: daysInMonth,
            hasData: outcomes.count == daysInMonth && outcomes.allSatisfy { $0 != nil }
        )
    }
}
