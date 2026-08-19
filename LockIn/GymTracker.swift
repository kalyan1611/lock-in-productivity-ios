import Combine
import Foundation

@MainActor
final class GymTracker: ObservableObject {
    static let shared = GymTracker()
    
    // MARK: - Gym Configuration
    
//    let targetGymDurationMinutes: Int = 45
    let targetGymDurationMinutes: Int = 1
    var targetGymDurationSeconds: TimeInterval {
        Double(targetGymDurationMinutes * 60)
    }
    
    private let minimumRecordedSessionSeconds: TimeInterval = 60
    
    // MARK: - Published State
    
    /// True after the user explicitly checks in via QR.
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
    
    // MARK: - Persistence
    
    private let userDefaults = UserDefaults.standard
    private let secondsKey = "LockIn_GymSeconds_"
    private let entryTimeKey = "LockIn_GymEntryTime"
    private let lastCheckOutDateKey = "LockIn_LastCheckOutDate"
    private let lastCheckInTimeKey = "LockIn_LastCheckInTime"
    private let lastCheckOutTimeKey = "LockIn_LastCheckOutTime"
    
    // MARK: - Initialization
    
    init() {
        restoreActiveSession()
        checkDailyCheckoutStatus()
        loadTodayAccumulatedTime()
    }
    
    // MARK: - Check In
    
    func checkIn() {
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
