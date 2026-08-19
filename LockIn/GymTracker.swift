import Foundation
import CoreLocation
import Combine
import UserNotifications

@MainActor
final class GymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = GymTracker()
    
    // MARK: - Gym Configuration
    
    private let gymLatitude: CLLocationDegrees = 17.38084
    private let gymLongitude: CLLocationDegrees = 78.36276
    private let gymRadiusMeters: CLLocationDistance = 40
    
    let targetGymDurationMinutes: Int = 45
    var targetGymDurationSeconds: TimeInterval {Double(targetGymDurationMinutes * 60)}
    
    private let minimumRecordedSessionSeconds: TimeInterval = 60
    
    // MARK: - Published State
    
    /// True when iOS determines the device is inside the gym geofence.
    @Published var isInsideGeofence = false
    
    /// True after the user explicitly presses Check In.
    @Published var isCheckedIn = false
    
    /// Time at which the current gym session was started.
    @Published var checkInDate: Date?
    
    /// Total accumulated gym time for today.
    @Published var totalSecondsToday: TimeInterval = 0
    
    /// True once today's accumulated gym time reaches 45 minutes.
    @Published var isGateUnlocked = false
    
    // MARK: - Location
    
    private let locationManager = CLLocationManager()
    
    private let gymRegionIdentifier = "GymRegion"
    
    // MARK: - Persistence
    
    private let userDefaults = UserDefaults.standard
    
    private let secondsKey = "LockIn_GymSeconds_"
    private let entryTimeKey = "LockIn_GymEntryTime"
    
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
        locationManager.showsBackgroundLocationIndicator = false
        
        restoreActiveSession()
        requestNotificationPermission()
        loadTodayAccumulatedTime()
    }
    
    // MARK: - Location Permission
    
    func requestLocationPermissionIfNeeded() {
        
        switch locationManager.authorizationStatus {
            
        case .notDetermined:
            
            locationManager.requestWhenInUseAuthorization()
            
        case .authorizedWhenInUse:
            
            locationManager.requestAlwaysAuthorization()
            
        case .authorizedAlways:
            
            setupGeofence()
            
        case .denied, .restricted:
            
            break
            
        @unknown default:
            
            break
        }
    }
    
    // MARK: - Authorization Callback
    
    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        
        switch manager.authorizationStatus {
            
        case .notDetermined:
            
            break
            
        case .authorizedWhenInUse:
            
            manager.requestAlwaysAuthorization()
            
        case .authorizedAlways:
            
            setupGeofence()
            
        case .denied, .restricted:
            
            break
            
        @unknown default:
            
            break
        }
    }
    
    // MARK: - Geofence
    
    private func setupGeofence() {
        
        // Remove any existing copy of our gym region.
        for region in locationManager.monitoredRegions {
            
            if region.identifier == gymRegionIdentifier {
                
                locationManager.stopMonitoring(for: region)
            }
        }
        
        let region = CLCircularRegion(
            center: gymCoordinate,
            radius: gymRadiusMeters,
            identifier: gymRegionIdentifier
        )
        
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager.startMonitoring(for: region)
        
        // Ask iOS whether we are already inside/outside.
        locationManager.requestState(for: region)
    }
    
    // MARK: - Notification Permission
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // Handle authorization result if needed
        }
    }
    
    // MARK: - Geofence Entry
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        
        guard region.identifier == "GymRegion" else {
            return
        }
        
        Task { @MainActor in
            self.isInsideGeofence = true
            
            // Only remind if not already checked in
            guard !self.isCheckedIn else { return }
            
            // <-- ADD THIS NOTIFICATION TRIGGER BLOCK
            let content = UNMutableNotificationContent()
            content.title = "Arrived at the Gym! 🏋️‍♂️"
            content.body = "You're inside the gym zone. Don't forget to check in!"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Triggers immediately
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    
    // MARK: - Geofence Exit
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        
        guard region.identifier == "GymRegion" else {
            return
        }
        
        Task { @MainActor in
            
            self.isInsideGeofence = false
            
            guard self.isCheckedIn else { return }
            
            // <-- ADD THIS EXIT NOTIFICATION BLOCK
            let content = UNMutableNotificationContent()
            content.title = "Left the Gym 🚶‍♂️"
            content.body = "You've left the gym zone. Don't forget to check out if your session is complete!"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Triggers immediately
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Current Geofence State
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        
        guard region.identifier == "GymRegion" else {
            return
        }
        
        Task { @MainActor in
            
            switch state {
                
            case .inside:
                
                self.isInsideGeofence = true
                
            case .outside:
                
                self.isInsideGeofence = false
                
            case .unknown:
                
                break
                
            @unknown default:
                
                break
            }
        }
    }
    
    // MARK: - Location Error
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        
        // Geofence monitoring continues independently.
        // Transient location errors are intentionally ignored.
    }
    
    // MARK: - Manual Check In
    
    func checkIn() {
        guard isInsideGeofence else { return }
        guard !isCheckedIn else { return }
        
        let now = Date()
        
        isCheckedIn = true
        checkInDate = now
        
        userDefaults.set(
            now.timeIntervalSince1970,
            forKey: entryTimeKey
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
        
        isCheckedIn = false
        self.checkInDate = nil
    }
    
    // MARK: - Restore Active Session
    
    private func restoreActiveSession() {
        
        guard let timestamp = userDefaults.object(
            forKey: entryTimeKey
        ) as? Double else {
            return
        }
        
        let date = Date(
            timeIntervalSince1970: timestamp
        )
        
        // Don't restore an obviously invalid future timestamp.
        guard date <= Date() else {
            userDefaults.removeObject(
                forKey: entryTimeKey
            )
            
            return
        }
        
        isCheckedIn = true
        checkInDate = date
    }
    
    // MARK: - Time Engine
    
    func calculateAndRecordSession() {
        
        guard let entryTimestamp = userDefaults.object(
            forKey: entryTimeKey
        ) as? Double else {
            return
        }
        
        let entryDate = Date(
            timeIntervalSince1970: entryTimestamp
        )
        
        let sessionDuration = Date().timeIntervalSince(
            entryDate
        )
        
        // Remove active session immediately.
        userDefaults.removeObject(
            forKey: entryTimeKey
        )
        
        // Ignore accidental sessions shorter than one minute.
        guard sessionDuration >= minimumRecordedSessionSeconds else {
            loadTodayAccumulatedTime()
            return
        }
        
        loadTodayAccumulatedTime()
        
        let newTotal =
        totalSecondsToday + sessionDuration
        
        saveTodayAccumulatedTime(newTotal)
    }
    
    // MARK: - Load Today's Time
    
    func loadTodayAccumulatedTime() {
        
        let todayKey = todayDateString()
        
        let storedSeconds =
        userDefaults.double(
            forKey: secondsKey + todayKey
        )
        
        var activeSession: TimeInterval = 0
        
        if let entryTimestamp = userDefaults.object(
            forKey: entryTimeKey
        ) as? Double {
            
            let entryDate = Date(
                timeIntervalSince1970: entryTimestamp
            )
            
            let elapsed =
            Date().timeIntervalSince(entryDate)
            
            activeSession = max(elapsed, 0)
        }
        
        totalSecondsToday =
        storedSeconds + activeSession
        
        isGateUnlocked =
        totalSecondsToday >= targetGymDurationSeconds
    }
    
    // MARK: - Save Today's Time
    
    private func saveTodayAccumulatedTime(
        _ seconds: TimeInterval
    ) {
        
        let todayKey = todayDateString()
        
        userDefaults.set(
            seconds,
            forKey: secondsKey + todayKey
        )
        
        totalSecondsToday = seconds
        
        isGateUnlocked =
        seconds >= targetGymDurationSeconds
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
