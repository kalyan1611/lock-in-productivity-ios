import SwiftUI

@main
struct StepSyncApp: App {
    /// Initialize Tracker at app start
    @StateObject private var gymTracker = GymTracker.shared

    init() {
        #if DEBUG
            // Debug builds run entirely on synthetic data — see
            // DebugDataSeeder. Seeding here, in init(), guarantees the data
            // exists before any view's .task (including ContentView's own
            // refresh()) runs its first sync.
            DebugDataSeeder.seedIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // DEBUG builds need nothing here — no HealthKit
                    // authorization, no LeetCode network call. ContentView's
                    // own refresh() already picks up the seeded data through
                    // the already-branched manager methods.
                    #if !DEBUG
                        do {
                            try await HealthKitManager.shared.requestAuthorization()
                            HealthKitManager.shared.enableBackgroundDelivery()
                            await HealthKitManager.shared.syncSteps()
                        } catch {
                            print("Startup error: \(error)")
                        }
                    #endif
                }
        }
    }
}
