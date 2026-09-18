import CoreLocation
import Foundation

/// Central place for every constant that points at something external
/// (a device, a service, a physical location) or that represents a
/// tunable daily goal. Nothing behavioral lives here — just values.
enum AppConfig {
    // MARK: - Gym

    enum Gym {
        // GPS coordinates of the gym. Check-in/check-out is only allowed
        // while the device is within `radiusMeters` of this point.
        //

        // gym coordinates
        static let latitude: CLLocationDegrees = 17.38099
        static let longitude: CLLocationDegrees = 78.36278

        /// How close (in meters) the device needs to be to count as "at the gym".
        static let radiusMeters: CLLocationDistance = 10

        static let targetDurationMinutes: Int = 45
        static let minimumRecordedSessionSeconds: TimeInterval = 60

        static var targetDurationSeconds: TimeInterval {
            Double(targetDurationMinutes * 60)
        }
    }

    // MARK: - Steps

    enum Steps {
        static let dailyTarget: Int = 10000
    }

    // MARK: - LeetCode

    enum LeetCode {
        static let defaultUsername = "kalyankumar239"
        static let dailyTargetProblems: Int = 10
        static let graphqlEndpoint = "https://leetcode.com/graphql"
    }

    // MARK: - Waive-Offs

    /// Limited weekly allowance per goal that lets a day count as handled
    /// without actually meeting the goal — tracked entirely on-device by
    /// WaiveOffManager now that there's no gate device to be the source of
    /// truth. Per-goal limits live here (not duplicated in WaiveOffManager)
    /// so WeeklyRetrospectiveCard's "X of weeklyTotal waived" denominator
    /// can never drift out of sync with what actually gets granted.
    enum WaiveOff {
        static let gym = 3
        static let steps = 2
        static let leetcode = 2
        static let weeklyTotal: Int = gym + steps + leetcode
    }

    // MARK: - UserDefaults Keys

    /// Every UserDefaults key in the app, in one place, so a typo becomes
    /// a compile error instead of a silent read-miss.
    enum DefaultsKey {
        static let leetcodeUsername = "leetcodeUsername"

        static let gymSecondsPrefix = "LockIn_GymSeconds_"
        static let gymEntryTime = "LockIn_GymEntryTime"
        static let gymLastCheckOutDate = "LockIn_LastCheckOutDate"
        static let gymLastCheckInTime = "LockIn_LastCheckInTime"
        static let gymLastCheckOutTime = "LockIn_LastCheckOutTime"

        /// UserDefaults — the rawValue (push/pull/legs) of whichever split
        /// was most recently *completed* (a session was persisted at
        /// checkout). `GymTracker.loadTodaySplit()` reads this to compute
        /// `.next` for today; missing means no split has ever been
        /// completed, so today defaults to `.push`.
        static let gymLastCompletedSplit = "LockIn_Gym_LastCompletedSplit"

        /// Keychain prefix, one entry per calendar day (mirrors
        /// gymSecondsPrefix's pattern) — the JSON-encoded `WorkoutSession`
        /// (split + per-exercise sets/reps/skip) logged that day. Read
        /// back by `GymTracker.workoutSession(on:)` for the tapped-bar
        /// detail view.
        static let gymWorkoutSessionPrefix = "LockIn_Gym_WorkoutSession_"

        /// One entry per calendar day, mirroring gymSecondsPrefix's pattern —
        /// caches LeetCode's daily solved-count locally since the API itself
        /// doesn't expose backdated history.
        static let leetcodeDailyCountPrefix = "LockIn_LeetCode_DailyCount_"

        /// Per-difficulty suffixes appended after `leetcodeDailyCountPrefix`
        /// + the date string, so the stacked chart can read back each
        /// difficulty's count for a given day, not just the day's total.
        static let leetcodeEasySuffix = "easy_"
        static let leetcodeMediumSuffix = "medium_"
        static let leetcodeHardSuffix = "hard_"

        /// UserDefaults-backed record of this week's waive-off usage (see
        /// WaiveOffManager) — how many of each goal's weekly allowance has
        /// been used, and which date (if any) each goal was last waived on.
        /// Rolls over automatically once the calendar week advances.
        static let waiveOffState = "LockIn_WaiveOffState"

        #if DEBUG
            /// Keychain (not UserDefaults, despite living in this "keys" enum
            /// for centralization) cache of synthetic per-day step totals —
            /// see DebugDataSeeder. Debug builds never write real HealthKit
            /// data, so this has its own prefix rather than reusing anything
            /// HealthKit-shaped.
            static let debugStepsPrefix = "LockIn_Debug_Steps_"

            /// Last calendar day (yyyy-MM-dd) DebugDataSeeder has generated
            /// data through. Missing = never seeded.
            static let debugSeedLastDateKey = "LockIn_Debug_SeedLastDate"
        #endif
    }
}
