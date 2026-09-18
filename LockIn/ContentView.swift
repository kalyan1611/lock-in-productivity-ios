import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var waiveOffManager = WaiveOffManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var waiveOffAlertType: WaiveOffManager.WaiveOffType?
    @State private var waiveOffError: String?
    @State private var selectedTab: GoalTab = .steps
    @State private var selectedPeriod: StatsPeriod = .week

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    ActivityCard(
                        selectedTab: $selectedTab,
                        selectedPeriod: $selectedPeriod,
                        healthKit: healthKit,
                        gymTracker: gymTracker,
                        leetCode: leetCode,
                        waiveOffStatus: waiveOffManager.waiveOffStatus,
                        onTapWaiveOff: { waiveOffAlertType = $0 }
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    // Pins content to at least the full available height so
                    // ActivityCard fills the screen exactly like the old
                    // two-card layout did. Wrapping in ScrollView at all is
                    // only here so .refreshable has something to attach to;
                    // a bare view can't support pull-to-refresh. On a screen
                    // too short for the card's minimum content, this also
                    // degrades gracefully into an actual scroll instead of
                    // clipping.
                    .frame(minHeight: geo.size.height)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await withCheckedContinuation { continuation in
                        Task {
                            await refresh()
                            continuation.resume()
                        }
                    }
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refresh() }
                }
            }
            .onAppear {
                UIRefreshControl.appearance().tintColor = UIColor(Color.green)
                gymTracker.requestLocationPermissionIfNeeded()
            }
            .alert("Use a waive-off?", isPresented: waiveOffPromptBinding) {
                Button("Cancel", role: .cancel) {
                    waiveOffAlertType = nil
                }
                Button("Use waive-off") {
                    confirmWaiveOff()
                }
            } message: {
                Text(waiveOffAlertMessage(for: waiveOffAlertType))
            }
            .alert("Couldn't use waive-off", isPresented: waiveOffErrorBinding) {
                Button("OK", role: .cancel) {
                    waiveOffError = nil
                }
            } message: {
                Text(waiveOffError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Waive-off alert plumbing

    private var waiveOffPromptBinding: Binding<Bool> {
        Binding(get: { waiveOffAlertType != nil }, set: {
            if !$0 {
                waiveOffAlertType = nil
            }
        })
    }

    private var waiveOffErrorBinding: Binding<Bool> {
        Binding(get: { waiveOffError != nil }, set: {
            if !$0 {
                waiveOffError = nil
            }
        })
    }

    private func confirmWaiveOff() {
        guard let type = waiveOffAlertType else { return }
        do {
            try waiveOffManager.useWaiveOff(type)
        } catch {
            waiveOffError = error.localizedDescription
        }
        waiveOffAlertType = nil
    }

    // MARK: - Waive-off alert message

    private func waiveOffProgressPercent(for type: WaiveOffManager.WaiveOffType) -> Int {
        let fraction: Double = switch type {
        case .steps:
            healthKit.targetSteps > 0
                ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps)
                : 0
        case .gym:
            gymTracker.targetGymDurationSeconds > 0
                ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds
                : 0
        case .leetcode:
            leetCode.targetProblems > 0
                ? Double(leetCode.totalTodayCount) / Double(leetCode.targetProblems)
                : 0
        }
        return min(max(Int((fraction * 100).rounded(.down)), 0), 100)
    }

    private func waiveOffAlertMessage(for type: WaiveOffManager.WaiveOffType?) -> String {
        let baseMessage = "This uses one of your limited weekly waive-off cards for today."
        guard let type else { return baseMessage }

        let percent = waiveOffProgressPercent(for: type)
        guard percent >= 50 else { return baseMessage }

        return "You're already \(percent)% of the way there — you may not need it. \(baseMessage)"
    }

    // MARK: - Sync

    /// Pulls each goal's latest live state, refreshes local waive-off
    /// status, and logs today's outcome per goal for the weekly
    /// retrospective. There's no gate device to round-trip through
    /// anymore, so this is just each manager updating itself from its own
    /// source (HealthKit, on-device gym/LeetCode caches, local waive-off
    /// state) — nothing here can fail in a way the user needs to see.
    private func refresh() async {
        gymTracker.checkDailyCheckoutStatus()
        gymTracker.refreshLocation()

        await healthKit.syncSteps()
        gymTracker.loadTodayAccumulatedTime()
        await leetCode.fetchTodaySolvedProblems()

        waiveOffManager.refresh()

        DailyOutcomeStore.recordOutcome(
            goal: .steps,
            metGoal: healthKit.areTodaysStepsCompleted,
            waivedToday: waiveOffManager.waiveOffStatus?.stepsWaivedToday ?? false
        )
        DailyOutcomeStore.recordOutcome(
            goal: .gym,
            metGoal: gymTracker.isGymSessionCompleted,
            waivedToday: waiveOffManager.waiveOffStatus?.gymWaivedToday ?? false
        )
        DailyOutcomeStore.recordOutcome(
            goal: .leetcode,
            metGoal: leetCode.isGoalMet,
            waivedToday: waiveOffManager.waiveOffStatus?.leetcodeWaivedToday ?? false
        )
    }
}

#Preview("iPhone") {
    ContentView()
}
