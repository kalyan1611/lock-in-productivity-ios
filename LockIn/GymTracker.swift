import Foundation
import CoreLocation
import Combine

@MainActor
final class GymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = GymTracker()
    
    // MARK: - Gym Configuration
    
    
    // flat
    //    private let gymLatitude: CLLocationDegrees = 17.38208
    //    private let gymLongitude: CLLocationDegrees = 78.36233
    
    // gym
    private let gymLatitude: CLLocationDegrees = 17.38084
    private let gymLongitude: CLLocationDegrees = 78.36276
    
    private let gymRadiusMeters: CLLocationDistance = 40
    
    let targetGymDurationMinutes: Int = 45
    var targetGymDurationSeconds: TimeInterval {
        Double(targetGymDurationMinutes * 60)
    }
    
    private let minimumRecordedSessionSeconds: TimeInterval = 60
    
    // MARK: - Published State
    
    /// True when the latest location check confirms the device is inside the gym radius.
    @Published var isInsideGeofence = false
    
    /// True after the user explicitly presses Check In.
    @Published var isCheckedIn = false
    
    /// True once the user has completed their session and checked out for today.
    @Published var hasCheckedOutToday = false
    
    /// Time at which the current gym session was started.
    @Published var checkInDate: Date?
    
    /// Total accumulated gym time for today.
    @Published var totalSecondsToday: TimeInterval = 0
    
    /// True once today's accumulated gym time reaches the target duration.
    @Published var isGateUnlocked = false
    
    /// Time the user checked in today. Persists (unlike `checkInDate`) after checkout,
    /// and only resets when a new day begins.
    @Published var lastCheckInDate: Date?
    
    /// Time the user checked out today. Persists after checkout and only resets
    /// when a new day begins.
    @Published var lastCheckOutDate: Date?
    
    // MARK: - Location
    
    private let locationManager = CLLocationManager()
    
    // MARK: - Persistence
    
    private let userDefaults = UserDefaults.standard
    private let secondsKey = "LockIn_GymSeconds_"
    private let entryTimeKey = "LockIn_GymEntryTime"
    private let lastCheckOutDateKey = "LockIn_LastCheckOutDate"
    private let lastCheckInTimeKey = "LockIn_LastCheckInTime"
    private let lastCheckOutTimeKey = "LockIn_LastCheckOutTime"
    
    // MARK: - Computed Properties
    
    var gymCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: gymLatitude,
            longitude: gymLongitude
        )
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
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // No background setup required anymore; just leave empty or handle if needed.
    }
    
    // MARK: - Manual Location Refresh (Pull-to-Refresh)
    
    /// Requests a single fresh location fix. Call this from your pull-to-refresh
    /// action to update `isInsideGeofence` on demand.
    func refreshLocation() {
        locationManager.requestLocation()
    }
    
    // MARK: - Live GPS Location Updates (One-Shot)
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latestLocation = locations.last else { return }
        
        Task { @MainActor in
            let distance = latestLocation.distance(
                from: CLLocation(latitude: gymLatitude, longitude: gymLongitude)
            )
            
            print("Distance to gym: \(distance)m")
            
            self.isInsideGeofence = (distance <= gymRadiusMeters)
        }
    }
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print(
            "Location manager failed with error: \(error.localizedDescription)"
        )
    }
    
    // MARK: - Manual Check In
    
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
        isGateUnlocked = totalSecondsToday >= targetGymDurationSeconds
    }
    
    // MARK: - Save Today's Time
    
    private func saveTodayAccumulatedTime(_ seconds: TimeInterval) {
        let todayKey = todayDateString()
        userDefaults.set(seconds, forKey: secondsKey + todayKey)
        totalSecondsToday = seconds
        isGateUnlocked = seconds >= targetGymDurationSeconds
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
