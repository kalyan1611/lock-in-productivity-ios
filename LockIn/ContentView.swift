import SwiftUI

// MARK: - Time Utilities

enum TimeUtils {
    static func isFreeTime(for date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = (weekday == 1 || weekday == 7) // 1 = Sunday, 7 = Saturday

        if isWeekend {
            return true
        }

        let currentHour = calendar.component(.hour, from: date)
        return currentHour >= 8 && currentHour < 23
    }
}

//
// LockIn's whole premise is a physical gate that only opens when the day's
// goals are met, so the UI leans into that: a dark "control panel" surface,
// one accent color that means "open" and one that means "restricted," and a
// ring motif — each goal closes its own ring, the hero dial is the sum of
// them. Nothing here is decorative; every ring, dot, and capsule reports a
// real piece of state from GymTracker / HealthKitManager / NetworkManager.

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private enum Palette {
    // MARK: - Backgrounds

    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x111111)
    static let surfaceRaised = Color(hex: 0x171B1F)
    static let surfaceStroke = Color(hex: 0x24292E)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xF5F6F7)
    static let textSecondary = Color(hex: 0x8A9199)
    static let textTertiary = Color(hex: 0x555C64)

    // MARK: - Semantic

    static let open = Color(hex: 0x55E6A5) // Goal met / unlocked
    static let started = Color(hex: 0x4F8FEF) // In progress
    static let locked = Color(hex: 0xFF5C5C) // Restricted
    static let waived = Color(hex: 0xE7A94B) // Waive-off used
    static let neutral = Color(hex: 0x4B525A) // Not started / inactive
}

private enum Typography {
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static var eyebrow: Font {
        .system(.caption, design: .monospaced).weight(.semibold)
    }
}

// MARK: - Content View

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

    private let checkButtonsHeight: CGFloat = 46

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    stepsCard
                    gymCard
                    leetCodeCard

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
                .padding(.bottom, 24)
            }
            .background(Palette.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
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
                Button("Cancel", role: .cancel) { waiveOffAlertType = nil }
                Button("Use waive-off") { confirmWaiveOff() }
            } message: {
                Text(waiveOffAlertMessage(for: waiveOffAlertType))
            }
            .alert("Couldn't use waive-off", isPresented: waiveOffErrorBinding) {
                Button("OK", role: .cancel) { waiveOffError = nil }
            } message: {
                Text(waiveOffError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

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

    // MARK: - Steps Card

    /// Mirrors the firmware's STEPS_PER_CREDIT_CHUNK (1000 steps = +10m,
    /// capped at the daily target) — kept in sync manually with
    /// dns_filter.ino's tieredMinutesFromProgress(). Computed locally from
    /// HealthKit data the app already has, rather than round-tripping
    /// through the ESP32, so it's live rather than only as fresh as the
    /// last /sync.
    private var stepsUntilNextChunk: Int? {
        let chunk = 1000
        let steps = healthKit.todaySteps
        let target = healthKit.targetSteps
        guard steps < target else { return nil }
        let nextThreshold = min(((steps / chunk) + 1) * chunk, target)
        let remaining = nextThreshold - steps
        return remaining > 0 ? remaining : nil
    }

    private var stepsCard: some View {
        let isCompleted = healthKit.areTodaysStepsCompleted
        let waived = network.waiveOffStatus?.stepsWaivedToday ?? false
        let progress = healthKit.targetSteps > 0
            ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps) : 0

        return GoalCardShell(
            title: "Steps",
            icon: "figure.walk",
            progress: progress,
            color: goalColor(progress: progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: network.waiveOffStatus?.stepsRemaining,
            onTapWaiveOff: { waiveOffAlertType = .steps }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(healthKit.todaySteps)")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("of \(healthKit.targetSteps) steps")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                if let remaining = stepsUntilNextChunk, remaining > 0 {
                    Text("\(remaining) to next +10m")
                        .font(.caption2)
                        .foregroundStyle(Palette.neutral)
                }
            }
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Gym Card

    private var gymCard: some View {
        let isCompleted = gymTracker.isGymSessionCompleted
        let waived = network.waiveOffStatus?.gymWaivedToday ?? false
        let progress = gymTracker.targetGymDurationSeconds > 0
            ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds : 0

        return GoalCardShell(
            title: "Workout",
            icon: "dumbbell.fill",
            progress: progress,
            color: goalColor(progress: progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: network.waiveOffStatus?.gymRemaining,
            onTapWaiveOff: { waiveOffAlertType = .gym }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(gymTracker.totalSecondsToday) / 60) min")
                    .font(Typography.display(22))
                    .foregroundStyle(Palette.textPrimary)
                Text("of \(gymTracker.targetGymDurationMinutes) min target")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                if !isCompleted {
                    Text("Full session: +45m")
                        .font(.caption2)
                        .foregroundStyle(Palette.neutral)
                }
            }
        } footer: {
            gymActionButton
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(checkInDate)
                let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)
                let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds
                let readyToCheckOut = canCheckOut && gymTracker.isInsideGeofence

                VStack(spacing: 10) {
                    Button {
                        gymTracker.checkOut()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: canCheckOut ? "figure.walk.departure" : "timer")
                            Text(canCheckOut ? "Check Out" : timeString(from: remaining))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: checkButtonsHeight)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(readyToCheckOut ? Palette.background : Palette.textSecondary)
                    .background(Capsule().fill(readyToCheckOut ? Palette.locked : Palette.surfaceStroke))
                    .disabled(!readyToCheckOut)

                    gymGuidanceLabel
                }
            }
        } else if gymTracker.hasCheckedOutToday {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Session complete")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.open)
                .frame(maxWidth: .infinity)
                .frame(height: checkButtonsHeight)
                .background(Capsule().fill(Palette.open.opacity(0.12)))

                Text(workoutDurationText)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        } else {
            VStack(spacing: 10) {
                Button {
                    gymTracker.checkIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text("Check In")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: checkButtonsHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(gymTracker.isInsideGeofence ? Palette.background : Palette.textSecondary)
                .background(Capsule().fill(gymTracker.isInsideGeofence ? Palette.open : Palette.surfaceStroke))
                .disabled(!gymTracker.isInsideGeofence)

                gymGuidanceLabel
            }
        }
    }

    private var gymGuidanceLabel: some View {
        Group {
            if gymTracker.isInsideGeofence {
                gymGuidanceRow(icon: "location.fill", text: "Inside gym zone", tint: Palette.open)
            } else if gymTracker.distanceToGym != nil {
                gymGuidanceRow(icon: "location", text: formattedDistance, tint: Palette.textSecondary)
            } else {
                gymGuidanceRow(icon: "location.slash", text: "Location unknown", tint: Palette.textSecondary)
            }
        }
        .font(.caption2)
    }

    private func gymGuidanceRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundStyle(tint)
    }

    private var formattedDistance: String {
        guard let distance = gymTracker.distanceToGym else { return "" }
        return distance >= 1000
            ? String(format: "%.1f km away", distance / 1000)
            : String(format: "%.0f m away", distance)
    }

    private var workoutDurationText: String {
        guard let inTime = gymTracker.lastCheckInDate, let outTime = gymTracker.lastCheckOutDate else {
            return "Workout logged for today"
        }
        let minutes = Int(outTime.timeIntervalSince(inTime) / 60)
        return "Workout duration: \(minutes) mins"
    }

    // MARK: - LeetCode Card

    private var leetCodeCard: some View {
        let isCompleted = leetCode.isGoalMet
        let waived = network.waiveOffStatus?.leetcodeWaivedToday ?? false

        return GoalCardShell(
            title: "Leetcode",
            icon: "chevron.left.forwardslash.chevron.right",
            progress: leetCode.progress,
            color: goalColor(progress: leetCode.progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: network.waiveOffStatus?.leetcodeRemaining,
            onTapWaiveOff: { waiveOffAlertType = .leetcode }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if leetCode.isLoading {
                    ProgressView()
                        .tint(Palette.textSecondary)
                } else {
                    Text("\(leetCode.totalTodayCount)")
                        .font(Typography.display(28))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                Text("of \(leetCode.targetProblems) problems")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        } footer: {
            difficultyBreakdown
                .padding(.top, 4)
        }
    }

    private var difficultyBreakdown: some View {
        HStack(spacing: 0) {
            difficultyColumn(label: "EASY", count: leetCode.easyTodayCount, creditLabel: "+5m", color: Palette.open)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "MEDIUM", count: leetCode.mediumTodayCount, creditLabel: "+10m", color: Palette.waived)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "HARD", count: leetCode.hardTodayCount, creditLabel: "+15m", color: Palette.locked)
        }
    }

    private func difficultyColumn(label: String, count: Int, creditLabel: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
            Text(creditLabel)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared Helpers

    /// Grey: not started. Blue: started, not yet complete. Green: goal met.
    /// Orange: a waive-off covered the day instead. `isCompleted` wins over
    /// `waived` since actually meeting the goal outranks skipping it.
    private func goalColor(progress: Double, isCompleted: Bool, waived: Bool) -> Color {
        if isCompleted {
            return Palette.open
        }
        if waived {
            return Palette.waived
        }
        if progress > 0 {
            return Palette.started
        }
        return Palette.neutral
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
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

    // MARK: - Waive-off Alert Message

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

// MARK: - Gate Hero (Device Status Card)

private struct GateHero: View {
    let isOpen: Bool?
    let deviceOnline: Bool
    let errorMessage: String?
    let goalsFullyMet: Bool?
    let availableToClaimMinutes: Int?
    let remainingMinutes: Int?
    let isClaiming: Bool
    let onClaim: () async -> Void

    private var tint: Color {
        switch isOpen {
        case .some(true): Palette.open
        case .some(false): Palette.locked
        case .none: Palette.neutral
        }
    }

    private var label: String {
        switch isOpen {
        case .some(true): goalsFullyMet == true ? "UNLOCKED FOR TODAY" : "OPEN — SPENDING BALANCE"
        case .some(false): TimeUtils.isFreeTime() ? "RESTRICTED" : "LOCKOUT HOURS"
        case .none: "UNKNOWN"
        }
    }

    private var icon: String {
        switch isOpen {
        case .some(true): "lock.open.fill"
        case .some(false): "lock.fill"
        case .none: "questionmark"
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0, m > 0 {
            return "\(h)h \(m)m"
        }
        if h > 0 {
            return "\(h)h"
        }
        return "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityRow

            if TimeUtils.isFreeTime() {
                Divider().overlay(Palette.surfaceStroke)
                creditRow
            }

            if let errorMessage {
                errorRow(errorMessage)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: Identity row (icon + status label + online pill)

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.easeInOut(duration: 0.3), value: isOpen)

            VStack(alignment: .leading, spacing: 3) {
                Text("GATE STATUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textSecondary)
                Text(label)
                    .font(Typography.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            onlinePill
        }
    }

    private var onlinePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(deviceOnline ? Palette.open : Palette.locked)
                .frame(width: 6, height: 6)
            Text(deviceOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.background.opacity(0.6)))
        .overlay(Capsule().stroke(Palette.surfaceStroke, lineWidth: 1))
    }

    // MARK: - Credit row

    private var creditIcon: String {
        if goalsFullyMet == true {
            return "checkmark.circle.fill"
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return "gift.fill"
        }

        if (remainingMinutes ?? 0) > 0 {
            return "clock.fill"
        }

        return "gift"
    }

    private var creditTint: Color {
        if goalsFullyMet == true {
            return Palette.open
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return Palette.open
        }

        if let remaining = remainingMinutes {
            return remaining > 0 ? Palette.textSecondary : Palette.locked
        }

        return Palette.textSecondary
    }

    private var showsClaimButton: Bool {
        goalsFullyMet != true && (availableToClaimMinutes ?? 0) > 0
    }

    private var creditRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: creditIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(creditTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                if goalsFullyMet == true {
                    Text("Goals complete — unlocked")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    // Credit that has been earned but not yet claimed.
                    if let available = availableToClaimMinutes, available > 0 {
                        HStack(spacing: 5) {
                            Text(isClaiming
                                ? "Claiming \(formatMinutes(available))…"
                                : "+\(formatMinutes(available)) available")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    // Credit already claimed and currently available to spend.
                    if let remaining = remainingMinutes, remaining > 0 {
                        Text("\(formatMinutes(remaining)) balance left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    } else if availableToClaimMinutes == nil || availableToClaimMinutes == 0 {
                        Text("No credit available")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if showsClaimButton {
                claimButton
            }
        }
    }

    private var claimButton: some View {
        Button {
            Task { await onClaim() }
        } label: {
            HStack(spacing: 5) {
                if isClaiming {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                } else {
                    Text("Claim")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Palette.open)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Palette.open.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Palette.open.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isClaiming)
    }

    // MARK: Error row

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(message)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.waived)
    }
}

// MARK: - Ring Progress

private struct RingProgress: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.surfaceStroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0015, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
    }
}

// MARK: - Goal Card Shell

private struct GoalCardShell<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let progress: Double
    let color: Color
    let isCompleted: Bool
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 16) {
                ZStack {
                    RingProgress(progress: progress, color: color, lineWidth: 7)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                content
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(title.uppercased())
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if !isCompleted, !waived, TimeUtils.isFreeTime(), let waiveRemaining {
                TicketBadge(remaining: waiveRemaining, action: onTapWaiveOff)
            }
        }
    }
}

/// Same recipe as GateHero's `onlinePill` and `claimButton` — translucent
/// dark fill + a 1pt stroke in the semantic color, rather than a solid
/// filled chip. "calendar.badge.minus" reads as "skip today" more directly
/// than a ticket icon, whose usual connotation is redeeming for something
/// rather than opting out of it.
private struct TicketBadge: View {
    let remaining: Int
    let action: () -> Void

    private var tint: Color {
        remaining > 0 ? Palette.waived : Palette.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.background.opacity(0.5)))
            .overlay(Capsule().stroke(remaining > 0 ? tint.opacity(0.4) : Palette.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(remaining <= 0)
    }
}
