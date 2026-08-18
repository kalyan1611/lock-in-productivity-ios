import SwiftUI
import BackgroundTasks

@main
struct StepSyncApp: App {
    
    // Initialize Tracker at app start
    @StateObject private var gymTracker = HardcodedGymTracker.shared

    init() {
        // Must happen before the app finishes launching, so register here.
        BackgroundTaskManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                        HealthKitManager.shared.enableBackgroundDelivery()
                        BackgroundTaskManager.shared.scheduleNextRefresh()
                        await HealthKitManager.shared.syncWithESP32()
                    } catch {
                        print("Startup error: \(error)")
                    }
                }
        }
    }
}
