import CoreLocation
import Foundation

/// Central place for every constant that points at something external
/// (a device, a service, a physical location) or that represents a
/// tunable daily goal. Nothing behavioral lives here — just values.
enum AppConfig {
    // MARK: - ESP32 Gate Controller

    enum Gate {
        /// LAN address of the ESP32. Update here if DHCP reassigns it,
        /// or move to a UserDefaults-backed override if it changes often.
        static let baseURL = "http://192.168.1.14"

        /// Fallback key used only if no override is saved in UserDefaults
        /// under `esp32APIKeyDefaultsKey`. Treat as a placeholder, not a secret.
        static let defaultAPIKey = "n6i8pBuDSSknFddjiHnTkZq8ptSjJmVPQpDra0K6qu8pj2C6NTheNHl27AdRM1O0"

        static let statusPath = "/status"
        static let syncPath = "/sync"
        static let claimPath = "/claim"
        static let waiveoffStatusPath = "/waiveoff/status"
        static let waiveoffPath = "/waiveoff"

        static let requestTimeout: TimeInterval = 4

        enum Method {
            static let get = "GET"
            static let post = "POST"
        }
    }

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

    // MARK: - UserDefaults Keys

    /// Every UserDefaults key in the app, in one place, so a typo becomes
    /// a compile error instead of a silent read-miss.
    enum DefaultsKey {
        static let esp32APIKeyOverride = "esp32APIKey"
        static let leetcodeUsername = "leetcodeUsername"

        static let gymSecondsPrefix = "LockIn_GymSeconds_"
        static let gymEntryTime = "LockIn_GymEntryTime"
        static let gymLastCheckOutDate = "LockIn_LastCheckOutDate"
        static let gymLastCheckInTime = "LockIn_LastCheckInTime"
        static let gymLastCheckOutTime = "LockIn_LastCheckOutTime"

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

        /// Last-known waive-off status, cached so the UI has something
        /// sane to show before the first successful fetch of a session
        /// and while offline.
        static let waiveOffStatusCache = "LockIn_WaiveOffStatusCache"
    }
}
