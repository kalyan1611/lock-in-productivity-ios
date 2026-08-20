import Combine
import Foundation
import HealthKit

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
    @Published var targetSteps: Int = AppConfig.Steps.dailyTarget
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    /// True once today's steps crosses targetSteps
    @Published var areTodaysStepsCompleted = false

    private init() {}

    /// Ask the user for read-only access to step count.
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

    /// Cumulative step count from local midnight to now.
    /// Gracefully returns 0 if no step samples exist yet for today.
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
                    let nsError = error as NSError
                    // Handle "No data available for the specified predicate" (HKError.errorNoData)
                    if nsError.domain == HKErrorDomain && nsError.code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: 0)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(sum))
            }
            healthStore.execute(query)
        }
    }

    /// Registers for background delivery and syncs when steps update.
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
                await self?.syncSteps()
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    /// Fetch latest step count and push all metrics to ESP32.
    @MainActor
    func syncSteps() async {
        do {
            let steps = try await fetchTodaySteps()
            todaySteps = steps
            areTodaysStepsCompleted = todaySteps >= targetSteps;
        } catch {
            print("Sync failed: \(error.localizedDescription)")
        }
    }
}
