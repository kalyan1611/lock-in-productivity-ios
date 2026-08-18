import Foundation
import CoreLocation
import Combine

@MainActor
class HardcodedGymTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = HardcodedGymTracker()

    // 📍 CHANGE THESE TO YOUR EXACT GYM COORDINATES
    private let gymLatitude: CLLocationDegrees = 17.38084
    private let gymLongitude: CLLocationDegrees = 78.36276
    private let gymRadiusMeters: CLLocationDistance = 40   // 40-meter boundary
    private let requiredDurationSeconds: TimeInterval = 45 * 60 // 45 Minutes (2,700 seconds)
    
    @Published var distanceFromGymMeters: Double? = nil
    @Published var totalSecondsToday: TimeInterval = 0
    @Published var isGateUnlocked: Bool = false
    @Published var isCurrentlyAtGym: Bool = false

    private let locationManager = CLLocationManager()
    private let userDefaults = UserDefaults.standard
    private let secondsKey = "LockIn_GymSeconds_"
    private let entryTimeKey = "LockIn_GymEntryTime"
    
    var gymCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: gymLatitude, longitude: gymLongitude)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        loadTodayAccumulatedTime()
        requestLocationPermissionAndStart()
    }

    private func requestLocationPermissionAndStart() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        setupHardcodedGeofence()
    }

    private func setupHardcodedGeofence() {
        let gymCenter = CLLocationCoordinate2D(latitude: gymLatitude, longitude: gymLongitude)
        let region = CLCircularRegion(center: gymCenter, radius: gymRadiusMeters, identifier: "HardcodedGymRegion")
        region.notifyOnEntry = true
        region.notifyOnExit = true

        locationManager.startMonitoring(for: region)
    }

    // MARK: - Location Updates (Live Distance)
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let gymLocation = CLLocation(latitude: gymLatitude, longitude: gymLongitude)
        let distance = location.distance(from: gymLocation)
        
        Task { @MainActor in
            self.distanceFromGymMeters = distance
        }
    }

    // MARK: - Geofence Delegate Events
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region.identifier == "HardcodedGymRegion" {
            Task { @MainActor in
                self.isCurrentlyAtGym = true
                self.userDefaults.set(Date().timeIntervalSince1970, forKey: self.entryTimeKey)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region.identifier == "HardcodedGymRegion" {
            Task { @MainActor in
                self.calculateAndRecordSession()
                self.isCurrentlyAtGym = false
                
                // Auto-sync steps and new gym time to ESP32 upon leaving the gym
                let steps = (try? await HealthKitManager.shared.fetchTodaySteps()) ?? 0
                let gymSeconds = Int(self.totalSecondsToday)
                _ = try? await NetworkManager.shared.sendSync(steps: steps, gymSeconds: gymSeconds)
            }
        }
    }

    // MARK: - Time Engine
    func calculateAndRecordSession() {
        guard let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double else { return }
        
        let entryDate = Date(timeIntervalSince1970: entryTimestamp)
        let sessionDuration = Date().timeIntervalSince(entryDate)
        
        userDefaults.removeObject(forKey: entryTimeKey)
        
        if sessionDuration >= 60 { // Ignore brief passes (<1 min)
            loadTodayAccumulatedTime()
            let newTotal = totalSecondsToday + sessionDuration
            saveTodayAccumulatedTime(newTotal)
        }
    }

    func loadTodayAccumulatedTime() {
        let todayKey = todayDateString()
        let storedSeconds = userDefaults.double(forKey: secondsKey + todayKey)
        
        var activeSession: TimeInterval = 0
        if let entryTimestamp = userDefaults.object(forKey: entryTimeKey) as? Double {
            activeSession = Date().timeIntervalSince(Date(timeIntervalSince1970: entryTimestamp))
        }

        self.totalSecondsToday = storedSeconds + activeSession
        self.isGateUnlocked = self.totalSecondsToday >= requiredDurationSeconds
    }

    private func saveTodayAccumulatedTime(_ seconds: TimeInterval) {
        let todayKey = todayDateString()
        userDefaults.set(seconds, forKey: secondsKey + todayKey)
        self.totalSecondsToday = seconds
        self.isGateUnlocked = seconds >= requiredDurationSeconds
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
