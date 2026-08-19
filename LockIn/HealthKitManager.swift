import Foundation
import HealthKit
import Combine

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    var errorDescription: String? {
        switch self {
        case .notAvailable: return "HealthKit is not available on this device"
        }
    }
}

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private var observerQuery: HKObserverQuery?
    
    @Published var todaySteps: Int = 0
    @Published var targetSteps: Int = 10000
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    private init() {}
    
    /// Ask the user for read-only access to step count. We never write
    /// anything back to Health, so `toShare` is empty.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: [stepType])
        let status = healthStore.authorizationStatus(for: stepType)
        await MainActor.run {
            self.authorizationStatus = status
        }
    }
    
    /// Cumulative step count from local midnight to now, using the
    /// device's current calendar/timezone — matches the bucketing logic
    /// from the earlier Shortcuts version. Doesn't touch @Published state,
    /// so no actor isolation needed here.
    func fetchTodaySteps() async throws -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: now, options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(sum))
            }
            healthStore.execute(query)
        }
    }
    
    /// Registers for background delivery so iOS wakes the app (subject to
    /// its own scheduling — not instant/guaranteed) whenever new step
    /// samples land in Health, and pushes an observer query that syncs
    /// automatically when that happens.
    func enableBackgroundDelivery() {
        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { success, error in
            if let error = error {
                print("enableBackgroundDelivery failed: \(error)")
            } else {
                print("enableBackgroundDelivery success: \(success)")
            }
        }
        
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                print("Observer query error: \(error!)")
                completionHandler()
                return
            }
            Task {
                await self?.syncWithESP32()
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }
    
    /// Fetch the latest step count and push it to the ESP32. Marked
    /// @MainActor since it's the one place that writes to the @Published
    /// todaySteps property — safe to call from background contexts
    /// (observer callback, BGAppRefreshTask) or a UI button either way,
    /// Swift will hop to the main actor automatically when awaited.
    @MainActor
    func syncWithESP32() async {
        do {
            let steps = try await fetchTodaySteps()
            self.todaySteps = steps
            
            // 1. Fetch gym time from GymTracker
            GymTracker.shared.loadTodayAccumulatedTime()
            let gymSeconds = Int(GymTracker.shared.totalSecondsToday)
            
            // 2. Send both metrics to ESP32 /sync
            let result = try await NetworkManager.shared.sendSync(steps: steps, gymSeconds: gymSeconds)
            print("Synced with ESP32! Goal met: \(result.goalMet)")
        } catch {
            print("Sync failed: \(error.localizedDescription)")
        }
    }
}
