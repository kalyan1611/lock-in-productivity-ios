import Foundation
import BackgroundTasks

/// Fallback periodic sync on top of HealthKit's background delivery.
/// iOS decides the actual timing based on usage patterns — this is a
/// best-effort supplement, not a guarantee. Combined with your ESP32
/// blocking internet until the goal is met, you're still incentivized to
/// open the app yourself, so this is a convenience, not the sole
/// enforcement mechanism.
///
/// IMPORTANT: taskIdentifier below must:
///   1. Match exactly what you add to Info.plist under
///      "Permitted background task scheduler identifiers"
///   2. Start with your app's bundle identifier prefix
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    static let taskIdentifier = "com.selfrule.tapas.refresh"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            // swiftlint:disable:next force_cast
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Earliest iOS will consider running it again; actual timing is
        // opportunistic and up to the system.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Always schedule the next one before doing work, in case this
        // run gets killed.
        scheduleNextRefresh()

        let syncTask = Task {
            await HealthKitManager.shared.syncWithESP32()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}
