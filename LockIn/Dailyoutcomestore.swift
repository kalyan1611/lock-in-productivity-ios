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

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func key(_ goal: Goal, _ date: Date) -> String {
        keyPrefix + goal.rawValue + "_" + dateString(date)
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
        let outcome: GoalOutcome = metGoal ? .met : (waivedToday ? .waived : .missed)
        KeychainStore.setString(outcome.rawValue, forKey: key(goal, date))
    }

    /// Reads back whatever was last recorded for that goal/date. `nil`
    /// means no entry exists — either the day hasn't happened yet, the
    /// app wasn't tracking outcomes yet on that date, or (only possible
    /// for today) no sync has completed yet today.
    static func outcome(goal: Goal, date: Date) -> GoalOutcome? {
        guard let raw = KeychainStore.string(forKey: key(goal, date)) else { return nil }
        return GoalOutcome(rawValue: raw)
    }

    /// Convenience for the retrospective card: every goal's outcome for
    /// one calendar day, keyed by `Goal`. Missing entries come back as
    /// `nil` in the dictionary rather than being omitted, so callers can
    /// tell "not tracked yet" apart from any real outcome.
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
}
