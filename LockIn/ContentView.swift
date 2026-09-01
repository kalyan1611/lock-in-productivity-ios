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

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    StepsCard(
                        healthKit: healthKit,
                        waived: network.waiveOffStatus?.stepsWaivedToday ?? false,
                        waiveRemaining: network.waiveOffStatus?.stepsRemaining,
                        onTapWaiveOff: { waiveOffAlertType = .steps }
                    )
                    GymCard(
                        gymTracker: gymTracker,
                        waived: network.waiveOffStatus?.gymWaivedToday ?? false,
                        waiveRemaining: network.waiveOffStatus?.gymRemaining,
                        onTapWaiveOff: { waiveOffAlertType = .gym }
                    )
                    LeetCodeCard(
                        leetCode: leetCode,
                        waived: network.waiveOffStatus?.leetcodeWaivedToday ?? false,
                        waiveRemaining: network.waiveOffStatus?.leetcodeRemaining,
                        onTapWaiveOff: { waiveOffAlertType = .leetcode }
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

                Spacer(minLength: 0)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await refresh() }
            .refreshable {
                await withCheckedContinuation { continuation in
                    Task {
                        await refresh()
                        continuation.resume()
                    }
                }
            }
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

            try await NetworkManager.shared.sendSync(
                steps: steps,
                gymSeconds: gymSeconds,
                leetCodeEasy: leetCode.easyTodayCount,
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
