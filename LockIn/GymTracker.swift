import Combine
import CoreLocation
import Foundation

@MainActor
final class GymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GymTracker()

    // MARK: - Gym Configuration

    let targetGymDurationMinutes: Int = AppConfig.Gym.targetDurationMinutes
    var targetGymDurationSeconds: TimeInterval {
        #if DEBUG
            return 60
        #else
            return AppConfig.Gym.targetDurationSeconds
        #endif
    }

    private let minimumRecordedSessionSeconds: TimeInterval = AppConfig.Gym.minimumRecordedSessionSeconds

    private let gymLatitude: CLLocationDegrees = AppConfig.Gym.latitude
    private let gymLongitude: CLLocationDegrees = AppConfig.Gym.longitude
    private let gymRadiusMeters: CLLocationDistance = AppConfig.Gym.radiusMeters

    // MARK: - Published State

    @Published var isInsideGeofence = false
    @Published var distanceToGym: CLLocationDistance?
    @Published var isCheckedIn = false
    @Published var hasCheckedOutToday = false
    @Published var checkInDate: Date?
    @Published var totalSecondsToday: TimeInterval = 0
    @Published var isGymSessionCompleted = false
    @Published var lastCheckInDate: Date?
    @Published var lastCheckOutDate: Date?

    /// Today's split in the push/pull/legs rotation. See `loadTodaySplit()`.
    @Published var todaySplit: WorkoutSplit = .push

    /// Editable exercise log for the in-progress (or just-finished) session.
    /// Seeded from `todaySplit.exercises` at check-in, mutated by
    /// GymChecklist, persisted at check-out.
    @Published var currentSessionLog: [ExerciseLog] = []

    // MARK: - Location

    private let locationManager = CLLocationManager()
    private let desiredHorizontalAccuracy: CLLocationAccuracy = 20
    private let locationRefreshTimeoutSeconds: UInt64 = 15
    private var locationRefreshTimeoutTask: Task<Void, Never>?
    private var bestLocationSoFar: CLLocation?

    // MARK: - Persistence

    private let userDefaults = UserDefaults.standard
    private let secondsKey = AppConfig.DefaultsKey.gymSecondsPrefix
    private let entryTimeKey = AppConfig.DefaultsKey.gymEntryTime
    private let lastCheckOutDateKey = AppConfig.DefaultsKey.gymLastCheckOutDate
    private let lastCheckInTimeKey = AppConfig.DefaultsKey.gymLastCheckInTime
    private let lastCheckOutTimeKey = AppConfig.DefaultsKey.gymLastCheckOutTime
    private let lastCompletedSplitKey = AppConfig.DefaultsKey.gymLastCompletedSplit
    private let sessionKeyPrefix = AppConfig.DefaultsKey.gymWorkoutSessionPrefix

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
        loadTodaySplit()
    }

    // MARK: - Location Permission

    func requestLocationPermissionIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {}

    // MARK: - Manual Location Refresh (Pull-to-Refresh)

    func refreshLocation() {
        bestLocationSoFar = nil
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()

        locationRefreshTimeoutTask?.cancel()
        locationRefreshTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: locationRefreshTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            print("Location refresh timed out after \(locationRefreshTimeoutSeconds)s — using best fix so far")
            locationManager.stopUpdatingLocation()
            applyBestFixIfNeeded()
        }
    }

    // MARK: - Live GPS Location Updates

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latestLocation = locations.last else { return }
        guard latestLocation.horizontalAccuracy > 0 else { return }

        Task { @MainActor in
            if self.bestLocationSoFar == nil ||
                latestLocation.horizontalAccuracy < self.bestLocationSoFar!.horizontalAccuracy
            {
                self.bestLocationSoFar = latestLocation
            }

            let distance = latestLocation.distance(from: CLLocation(latitude: gymLatitude, longitude: gymLongitude))
            self.distanceToGym = distance
            self.isInsideGeofence = (distance <= gymRadiusMeters)

            if latestLocation.horizontalAccuracy <= desiredHorizontalAccuracy {
                manager.stopUpdatingLocation()
                self.locationRefreshTimeoutTask?.cancel()
                self.locationRefreshTimeoutTask = nil
            }
        }
    }

    private func applyBestFixIfNeeded() {
        guard let best = bestLocationSoFar else { return }
        let distance = best.distance(from: CLLocation(latitude: gymLatitude, longitude: gymLongitude))
        distanceToGym = distance
        isInsideGeofence = (distance <= gymRadiusMeters)
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }

    // MARK: - Check In

    func checkIn() {
        #if DEBUG
            let locationOK = true
        #else
            let locationOK = isInsideGeofence
        #endif
        guard locationOK else { return }
        guard !isCheckedIn else { return }
        guard !hasCheckedOutToday else { return }

        let now = Date()
        isCheckedIn = true
        checkInDate = now
        lastCheckInDate = now

        userDefaults.set(now.timeIntervalSince1970, forKey: entryTimeKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: lastCheckInTimeKey)

        startSessionLog()
    }

    // MARK: - Manual Check Out

    func checkOut() {
        guard isCheckedIn else { return }
        guard let checkInDate else { return }

        let elapsed = Date().timeIntervalSince(checkInDate)
        guard elapsed >= targetGymDurationSeconds else { return }

        calculateAndRecordSession()
        persistSessionLog()

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
        guard let timestamp = userDefaults.object(forKey: entryTimeKey) as? Double else { return }
        let date = Date(timeIntervalSince1970: timestamp)
        guard date <= Date() else {
            userDefaults.removeObject(forKey: entryTimeKey)
            return
        }
        isCheckedIn = true
        checkInDate = date
    }

    // MARK: - Check Daily Checkout Status

    func checkDailyCheckoutStatus() {
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
        loadTodaySplit()
    }

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
        guard let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double else { return }

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

    func loadTodayAccumulatedTime() {
        let todayKey = todayDateString()
        let storedSeconds = KeychainStore.double(forKey: secondsKey + todayKey)

        var activeSession: TimeInterval = 0
        if let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double {
            let entryDate = Date(timeIntervalSince1970: entryTimestamp)
            let elapsed = Date().timeIntervalSince(entryDate)
            activeSession = max(elapsed, 0)
        }

        totalSecondsToday = storedSeconds + activeSession
        isGymSessionCompleted = totalSecondsToday >= targetGymDurationSeconds
    }

    private func saveTodayAccumulatedTime(_ seconds: TimeInterval) {
        let todayKey = todayDateString()
        KeychainStore.setDouble(seconds, forKey: secondsKey + todayKey)
        totalSecondsToday = seconds
        isGymSessionCompleted = seconds >= targetGymDurationSeconds
    }

    func secondsHistory(days: Int, endingOn endDate: Date = Date()) -> [(date: Date, seconds: Double)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"

        var result: [(date: Date, seconds: Double)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            let key = secondsKey + formatter.string(from: day)
            let seconds = KeychainStore.double(forKey: key)
            result.append((date: calendar.startOfDay(for: day), seconds: seconds))
        }
        return result
    }

    // MARK: - Workout Split & Session Logging

    /// Today's split rotates off whichever split was last *completed* —
    /// not the weekday — so a skipped day never desyncs the cycle from the
    /// calendar. If today's session is already logged (e.g. relaunching
    /// the app after finishing), sticks to that recorded split instead of
    /// recomputing, so it can't flip out from under a completed session.
    private func loadTodaySplit() {
        if let existing = workoutSession(on: Date()) {
            todaySplit = existing.split
            return
        }
        guard let lastRaw = userDefaults.string(forKey: lastCompletedSplitKey),
              let last = WorkoutSplit(rawValue: lastRaw)
        else {
            todaySplit = .push
            return
        }
        todaySplit = last.next
    }

    /// Called on check-in — seeds the editable log with the prescribed
    /// sets/reps. "Assume all sets and reps as planned" is the default;
    /// GymChecklist lets you correct it before checkout.
    private func startSessionLog() {
        currentSessionLog = todaySplit.exercises.map {
            ExerciseLog(name: $0.name, reps: 0, setsDone: 0, skipped: false)
        }
    }

    private func persistSessionLog() {
        let session = WorkoutSession(split: todaySplit, exercises: currentSessionLog)
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8)
        else { return }
        KeychainStore.setString(json, forKey: sessionKeyPrefix + todayDateString())
        userDefaults.set(todaySplit.rawValue, forKey: lastCompletedSplitKey)
    }

    /// Logged workout for a given calendar day, if one was recorded — nil
    /// for rest days or days before this feature shipped.
    func workoutSession(on date: Date) -> WorkoutSession? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let key = sessionKeyPrefix + formatter.string(from: date)
        guard let json = KeychainStore.string(forKey: key),
              let data = json.data(using: .utf8),
              let session = try? JSONDecoder().decode(WorkoutSession.self, from: data)
        else { return nil }
        return session
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
