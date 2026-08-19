import SwiftUI
import BackgroundTasks

@main
struct StepSyncApp: App {
    
    // Initialize Tracker at app start
    @StateObject private var gymTracker = GymTracker.shared
    
    init() {
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                        HealthKitManager.shared.enableBackgroundDelivery()
                        await HealthKitManager.shared.syncWithESP32()
                    } catch {
                        print("Startup error: \(error)")
                    }
                }
        }
    }
}
