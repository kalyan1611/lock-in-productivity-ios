import Foundation
import CoreLocation
import Combine

@MainActor
final class GymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = GymTracker()
    
    // MARK: - Gym Configuration
    
    private let gymLatitude: CLLocationDegrees = 17.38084
    private let gymLongitude: CLLocationDegrees = 78.36276
    private let gymRadiusMeters: CLLocationDistance = 40
    private let requiredDurationSeconds: TimeInterval = 45 * 60
    
    // MARK: - Published State
    
    @Published var distanceFromGymMeters: Double?
    @Published var totalSecondsToday: TimeInterval = 0
    @Published var isGateUnlocked = false
    @Published var isCurrentlyAtGym = false
    
    // MARK: - Location
    
    private let locationManager = CLLocationManager()
    
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
        
        loadTodayAccumulatedTime()
    }
    
    // MARK: - Location Permission
    
    func requestLocationPermissionIfNeeded() {
        
        guard CLLocationManager.locationServicesEnabled() else {
            return
        }
        
        switch locationManager.authorizationStatus {
            
        case .notDetermined:
            
            // First ask for When In Use.
            locationManager.requestWhenInUseAuthorization()
            
        case .authorizedWhenInUse:
            
            // Once When In Use has been granted,
            // ask for Always authorization.
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
            
            // User has granted foreground location.
            // Now request background location permission.
            manager.requestAlwaysAuthorization()
            
        case .authorizedAlways:
            
            // We now have the permission required
            // for background geofencing.
            setupGeofence()
            
        case .denied, .restricted:
            
            break
            
        @unknown default:
            
            break
        }
    }
    
    // MARK: - Geofence
    
    private func setupGeofence() {
        
        // Remove an existing copy of our gym region.
        for region in locationManager.monitoredRegions {
            
            if region.identifier == "GymRegion" {
                locationManager.stopMonitoring(for: region)
            }
        }
        
        let gymCenter = CLLocationCoordinate2D(
            latitude: gymLatitude,
            longitude: gymLongitude
        )
        
        let region = CLCircularRegion(
            center: gymCenter,
            radius: gymRadiusMeters,
            identifier: "GymRegion"
        )
        
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager.startMonitoring(for: region)
    }
    
    // MARK: - Foreground Location Updates
    
    /// Starts continuous location updates only while
    /// the app is visible.
    func startForegroundLocationUpdates() {
        
        guard CLLocationManager.locationServicesEnabled() else {
            return
        }
        
        switch locationManager.authorizationStatus {
            
        case .authorizedAlways,
                .authorizedWhenInUse:
            
            locationManager.desiredAccuracy =
            kCLLocationAccuracyBest
            
            locationManager.distanceFilter = 5
            
            locationManager.startUpdatingLocation()
            
        default:
            
            break
        }
    }
    
    /// Stops continuous GPS updates when the app
    /// leaves the foreground.
    ///
    /// Geofencing continues to work.
    func stopForegroundLocationUpdates() {
        
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - Live Location Updates
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        
        guard let location = locations.last else {
            return
        }
        
        let gymLocation = CLLocation(
            latitude: gymLatitude,
            longitude: gymLongitude
        )
        
        let distance = location.distance(
            from: gymLocation
        )
        
        Task { @MainActor in
            
            self.distanceFromGymMeters = distance
            
            self.isCurrentlyAtGym =
            distance <= self.gymRadiusMeters
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
            
            self.isCurrentlyAtGym = true
            
            let entryTimestamp =
            Date().timeIntervalSince1970
            
            self.userDefaults.set(
                entryTimestamp,
                forKey: self.entryTimeKey
            )
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
            
            self.calculateAndRecordSession()
            
            self.isCurrentlyAtGym = false
        }
    }
    
    // MARK: - Location Error
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Ignore transient location errors.
        // Geofence monitoring continues independently.
    }
    
    // MARK: - Time Engine
    
    func calculateAndRecordSession() {
        
        guard let entryTimestamp =
                userDefaults.object(
                    forKey: entryTimeKey
                ) as? Double
        else {
            return
        }
        
        let entryDate =
        Date(timeIntervalSince1970: entryTimestamp)
        
        let sessionDuration =
        Date().timeIntervalSince(entryDate)
        
        userDefaults.removeObject(
            forKey: entryTimeKey
        )
        
        // Ignore accidental passes shorter than one minute.
        if sessionDuration >= 60 {
            
            loadTodayAccumulatedTime()
            
            let newTotal =
            totalSecondsToday + sessionDuration
            
            saveTodayAccumulatedTime(newTotal)
        }
    }
    
    // MARK: - Load Today's Time
    
    func loadTodayAccumulatedTime() {
        
        let todayKey = todayDateString()
        
        let storedSeconds =
        userDefaults.double(
            forKey: secondsKey + todayKey
        )
        
        var activeSession: TimeInterval = 0
        
        if let entryTimestamp =
            userDefaults.object(
                forKey: entryTimeKey
            ) as? Double {
            
            activeSession =
            Date().timeIntervalSince(
                Date(timeIntervalSince1970: entryTimestamp)
            )
        }
        
        totalSecondsToday =
        storedSeconds + activeSession
        
        isGateUnlocked =
        totalSecondsToday >= requiredDurationSeconds
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
        seconds >= requiredDurationSeconds
    }
    
    // MARK: - Date
    
    private func todayDateString() -> String {
        
        let formatter = DateFormatter()
        
        formatter.dateFormat = "yyyy-MM-dd"
        
        return formatter.string(from: Date())
    }
}
