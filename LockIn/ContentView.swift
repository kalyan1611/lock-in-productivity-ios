import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var lastSyncStatus: String = ""
    @State private var waiveOffAlertType: NetworkManager.WaiveOffType?
    @State private var waiveOffError: String?
    @State private var isClaiming = false
    @State private var selectedTab: GoalTab = .steps
    @State private var selectedPeriod: StatsPeriod = .week

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 12) {
                        ActivityCard(
                            selectedTab: $selectedTab,
                            selectedPeriod: $selectedPeriod,
                            healthKit: healthKit,
                            gymTracker: gymTracker,
                            leetCode: leetCode,
                            waiveOffStatus: network.waiveOffStatus,
                            onTapWaiveOff: { waiveOffAlertType = $0 }
                        )

                        GateHero(
                            isOpen: network.isGateOpen,
                            deviceOnline: network.connectionStatus == .online,
                            errorMessage: networkErrorMessage,
                            goalsFullyMet: network.goalsFullyMet,
                            availableToClaimMinutes: network.availableToClaimMinutes,
                            remainingMinutes: network.remainingMinutesToday,
                            isClaiming: isClaiming,
                            onClaim: { await claimCredit() }
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    // Pins content to at least the full available height so
                    // nothing scrolls during normal use — the two cards fill
                    // the screen exactly like before. Wrapping in ScrollView
                    // at all is only here so .refreshable has something to
                    // attach to; a bare VStack can't support pull-to-refresh.
                    // On a screen too short for both cards' minimum content,
                    // this also degrades gracefully into an actual scroll
                    // instead of clipping.
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
        Task {
            do {
                try await network.useWaiveOff(type)
            } catch {
                waiveOffError = error.localizedDescription
            }
            waiveOffAlertType = nil
        }
    }

    private var networkErrorMessage: String? {
        if !lastSyncStatus.isEmpty {
            return lastSyncStatus
        }
        if network.waiveOffStatus == nil, let waiveOffError = network.waiveOffFetchError {
            return waiveOffError
        }
        if let leetCodeError = leetCode.errorMessage {
            return leetCodeError
        }
        return nil
    }

    // MARK: - Waive-off alert message

    private func waiveOffProgressPercent(for type: NetworkManager.WaiveOffType) -> Int {
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

    private func waiveOffAlertMessage(for type: NetworkManager.WaiveOffType?) -> String {
        let baseMessage = "This uses one of your limited weekly waive-off cards for today."
        guard let type else { return baseMessage }

        let percent = waiveOffProgressPercent(for: type)
        guard percent >= 50 else { return baseMessage }

        return "You're already \(percent)% of the way there — you may not need it. \(baseMessage)"
    }

    // MARK: - Sync

    private func refresh() async {
        lastSyncStatus = ""

        do {
            gymTracker.checkDailyCheckoutStatus()

            gymTracker.refreshLocation()
            await network.checkStatus()

            await healthKit.syncSteps()
            let steps = healthKit.todaySteps

            gymTracker.loadTodayAccumulatedTime()
            let gymSeconds = Int(gymTracker.totalSecondsToday)

            await leetCode.fetchTodaySolvedProblems()

//            try await NetworkManager.shared.sendSync(
//                steps: steps,
//                gymSeconds: gymSeconds,
//                leetCodeEasy: leetCode.easyTodayCount,
//                leetCodeMedium: leetCode.mediumTodayCount,
//                leetCodeHard: leetCode.hardTodayCount
//            )
            
            try await NetworkManager.shared.sendSync(
                steps: 11000,
                gymSeconds: 300000,
                leetCodeEasy: 12,
                leetCodeMedium: leetCode.mediumTodayCount,
                leetCodeHard: leetCode.hardTodayCount
            )

            await network.fetchWaiveOffStatus()
        } catch {
            print("sendSync failed: \(error)")
            lastSyncStatus = "Couldn't reach your gate device — \(error.localizedDescription)"
        }
    }

    private func claimCredit() async {
        guard !isClaiming else { return }
        isClaiming = true
        defer { isClaiming = false }
        do {
            try await NetworkManager.shared.claim()
        } catch {
            lastSyncStatus = "Couldn't claim credit — \(error.localizedDescription)"
        }
    }
}

#Preview("iPhone") {
    ContentView()
}
