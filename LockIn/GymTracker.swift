import Combine
import CoreLocation
import Foundation

@MainActor
final class GymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GymTracker()

    // MARK: - Gym Configuration

    let targetGymDurationMinutes: Int = AppConfig.Gym.targetDurationMinutes
    var targetGymDurationSeconds: TimeInterval {
        AppConfig.Gym.targetDurationSeconds
    }

    private let minimumRecordedSessionSeconds: TimeInterval = AppConfig.Gym.minimumRecordedSessionSeconds

    private let gymLatitude: CLLocationDegrees = AppConfig.Gym.latitude
    private let gymLongitude: CLLocationDegrees = AppConfig.Gym.longitude
    private let gymRadiusMeters: CLLocationDistance = AppConfig.Gym.radiusMeters

    // MARK: - Published State

    /// True when the latest location check confirms the device is inside the gym radius.
    @Published var isInsideGeofence = false

    /// Distance to the gym in meters, updated on location fetches.
    @Published var distanceToGym: CLLocationDistance?

    /// True after the user explicitly checks in.
    @Published var isCheckedIn = false

    /// True once the user has completed their session and checked out for today.
    @Published var hasCheckedOutToday = false

    /// Time at which the current gym session was started.
    @Published var checkInDate: Date?

    /// Total accumulated gym time for today.
    @Published var totalSecondsToday: TimeInterval = 0

    /// True once today's accumulated gym time reaches the target duration.
    @Published var isGymSessionCompleted = false

    /// Time the user checked in today. Persists (unlike `checkInDate`) after checkout,
    /// and only resets when a new day begins.
    @Published var lastCheckInDate: Date?

    /// Time the user checked out today. Persists after checkout and only resets
    /// when a new day begins.
    @Published var lastCheckOutDate: Date?

    // MARK: - Location

    private let locationManager = CLLocationManager()

    /// Bounds how long we wait for a fix accurate enough to trust before
    /// falling back to whatever reading we have.
    private var locationTimeoutTask: Task<Void, Never>?

    // MARK: - Persistence

    private let userDefaults = UserDefaults.standard
    private let secondsKey = AppConfig.DefaultsKey.gymSecondsPrefix
    private let entryTimeKey = AppConfig.DefaultsKey.gymEntryTime
    private let lastCheckOutDateKey = AppConfig.DefaultsKey.gymLastCheckOutDate
    private let lastCheckInTimeKey = AppConfig.DefaultsKey.gymLastCheckInTime
    private let lastCheckOutTimeKey = AppConfig.DefaultsKey.gymLastCheckOutTime

    // MARK: - Computed Properties

    var gymCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: gymLatitude, longitude: gymLongitude)
    }

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        restoreActiveSession()
        checkDailyCheckoutStatus()
        loadTodayAccumulatedTime()
    }

    // MARK: - Location Permission

    func requestLocationPermissionIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        // No background setup required; permission changes are picked up on next refresh.
    }

    // MARK: - Manual Location Refresh (Pull-to-Refresh)

    /// Requests a location fix and keeps listening until either a fix
    /// accurate enough to trust arrives, or `locationRefreshTimeout` elapses —
    /// at which point we stop and use the best fix received so far.
    func refreshLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()

        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppConfig.Gym.locationRefreshTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.locationManager.stopUpdatingLocation()
        }
    }

    // MARK: - Live GPS Location Updates

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latestLocation = locations.last, latestLocation.horizontalAccuracy >= 0 else { return }

        Task { @MainActor in
            let distance = latestLocation.distance(from: CLLocation(latitude: gymLatitude, longitude: gymLongitude))

            print("Accurate distance to gym: \(distance)m (Accuracy: \(latestLocation.horizontalAccuracy)m) — current location: \(latestLocation.coordinate.latitude), \(latestLocation.coordinate.longitude)")

            self.distanceToGym = distance
            self.isInsideGeofence = (distance <= gymRadiusMeters)

            // Keep listening for a better fix until accuracy is good enough to
            // trust; the timeout above is the fallback if that never arrives.
            if latestLocation.horizontalAccuracy <= AppConfig.Gym.desiredAccuracyMeters {
                self.locationTimeoutTask?.cancel()
                manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }

    // MARK: - Check In

    func checkIn() {
        guard isInsideGeofence else { return }
        guard !isCheckedIn else { return }
        guard !hasCheckedOutToday else { return }

        let now = Date()

        isCheckedIn = true
        checkInDate = now
        lastCheckInDate = now

        userDefaults.set(
            now.timeIntervalSince1970,
            forKey: entryTimeKey
        )

        userDefaults.set(
            now.timeIntervalSince1970,
            forKey: lastCheckInTimeKey
        )
    }

    // MARK: - Manual Check Out

    func checkOut() {
        guard isCheckedIn else { return }
        guard let checkInDate else { return }

        let elapsed = Date().timeIntervalSince(checkInDate)

        guard elapsed >= targetGymDurationSeconds else {
            return
        }

        calculateAndRecordSession()

        let now = Date()

        isCheckedIn = false
        self.checkInDate = nil
        hasCheckedOutToday = true
        lastCheckOutDate = now

        userDefaults.set(todayDateString(), forKey: lastCheckOutDateKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: lastCheckOutTimeKey)
    }

    // MARK: - Restore Active Session

    private func restoreActiveSession() {
        guard let timestamp = userDefaults.object(forKey: entryTimeKey) as? Double else {
            return
        }

        let date = Date(timeIntervalSince1970: timestamp)

        guard date <= Date() else {
            userDefaults.removeObject(forKey: entryTimeKey)
            return
        }

        isCheckedIn = true
        checkInDate = date
    }

    // MARK: - Check Daily Checkout Status

    private func checkDailyCheckoutStatus() {
        let lastCheckoutDate = userDefaults.string(forKey: lastCheckOutDateKey)
        let today = todayDateString()

        if lastCheckoutDate == today {
            hasCheckedOutToday = true
        } else {
            hasCheckedOutToday = false
            userDefaults.removeObject(forKey: lastCheckOutDateKey)
            userDefaults.removeObject(forKey: lastCheckInTimeKey)
            userDefaults.removeObject(forKey: lastCheckOutTimeKey)
        }

        loadPersistedCheckTimes()
    }

    // MARK: - Load Persisted Check In / Check Out Times

    private func loadPersistedCheckTimes() {
        if let timestamp = userDefaults.object(forKey: lastCheckInTimeKey) as? Double {
            lastCheckInDate = Date(timeIntervalSince1970: timestamp)
        } else {
            lastCheckInDate = nil
        }

        if let timestamp = userDefaults.object(forKey: lastCheckOutTimeKey) as? Double {
            lastCheckOutDate = Date(timeIntervalSince1970: timestamp)
        } else {
            lastCheckOutDate = nil
        }
    }

    // MARK: - Time Engine

    func calculateAndRecordSession() {
        guard let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double else {
            return
        }

        let entryDate = Date(timeIntervalSince1970: entryTimestamp)
        let sessionDuration = Date().timeIntervalSince(entryDate)

        userDefaults.removeObject(forKey: entryTimeKey)

        guard sessionDuration >= minimumRecordedSessionSeconds else {
            loadTodayAccumulatedTime()
            return
        }

        loadTodayAccumulatedTime()
        let newTotal = totalSecondsToday + sessionDuration
        saveTodayAccumulatedTime(newTotal)
    }

    // MARK: - Load Today's Time

    func loadTodayAccumulatedTime() {
        let todayKey = todayDateString()
        let storedSeconds = userDefaults.double(forKey: secondsKey + todayKey)

        var activeSession: TimeInterval = 0
        if let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double {
            let entryDate = Date(timeIntervalSince1970: entryTimestamp)
            let elapsed = Date().timeIntervalSince(entryDate)
            activeSession = max(elapsed, 0)
        }

        totalSecondsToday = storedSeconds + activeSession
        isGymSessionCompleted = totalSecondsToday >= targetGymDurationSeconds

        if isGymSessionCompleted {
            StreakManager.shared.recordCompletion(for: .gym)
        }
    }

    // MARK: - Save Today's Time

    private func saveTodayAccumulatedTime(_ seconds: TimeInterval) {
        let todayKey = todayDateString()
        userDefaults.set(seconds, forKey: secondsKey + todayKey)
        totalSecondsToday = seconds
        isGymSessionCompleted = seconds >= targetGymDurationSeconds

        if isGymSessionCompleted {
            StreakManager.shared.recordCompletion(for: .gym)
        }
    }

    // MARK: - Date

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
