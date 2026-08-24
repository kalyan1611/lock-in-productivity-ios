import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var lastSyncStatus: String = ""

    // MARK: - Waive-off UI state

    @State private var waiveOffAlertType: NetworkManager.WaiveOffType?
    @State private var waiveOffError: String?

    private var checkButtonsHeight: CGFloat = 38

    /// One spacing scale, used everywhere in this screen instead of ad hoc
    /// numbers, so the same kind of relationship always gets the same gap.
    private enum Spacing {
        /// Icon ↔ tiny inline text (location caption, ticket count).
        static let micro: CGFloat = 4
        /// Icon ↔ label inside a button, or a small icon-led detail row.
        static let iconText: CGFloat = 6
        /// Row ↔ row within a single card (header, body, footer).
        static let row: CGFloat = 8
        /// An interactive control ↔ its explanatory caption below it.
        static let group: CGFloat = 12
        /// Card ↔ next card's section (Form section spacing).
        static let section: CGFloat = 40
        /// Vertical breathing room inside a card, above/below its content.
        static let cardPadding: CGFloat = 4
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section() { stepsCard }
                Section() { gymCard }
                Section() { leetCodeCard }
                Section() { deviceStatusCard }
            }
            .listSectionSpacing(Spacing.section)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await refresh()
            }
            .refreshable {
                await refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refresh() }
                }
            }
            .onAppear {
                UIRefreshControl.appearance().tintColor = .green
                gymTracker.requestLocationPermissionIfNeeded()
            }
            .alert("Use a waive-off?", isPresented: Binding(
                get: { waiveOffAlertType != nil },
                set: {
                    if !$0 {
                        waiveOffAlertType = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) { waiveOffAlertType = nil }
                Button("Use waive-off") {
                    if let type = waiveOffAlertType {
                        Task {
                            do {
                                try await network.useWaiveOff(type)
                            } catch {
                                waiveOffError = error.localizedDescription
                            }
                            waiveOffAlertType = nil
                        }
                    }
                }
            } message: {
                Text(waiveOffAlertMessage(for: waiveOffAlertType))
            }
            .alert("Couldn't use waive-off", isPresented: Binding(
                get: { waiveOffError != nil },
                set: {
                    if !$0 {
                        waiveOffError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { waiveOffError = nil }
            } message: {
                Text(waiveOffError ?? "")
            }
        }
    }

    // MARK: - 1. Steps Card

    @ViewBuilder
    private var stepsCard: some View {
        let isGoalCompleted = healthKit.areTodaysStepsCompleted
        VStack(alignment: .leading, spacing: Spacing.row) {
            HStack {
                Label("Steps", systemImage: "figure.walk")
                    .font(.subheadline)
                    .bold()

                Spacer()

                let stepsWaived = network.waiveOffStatus?.stepsWaivedToday ?? false

                if !isGoalCompleted, !stepsWaived, let status = network.waiveOffStatus {
                    waiveOffBadge(remaining: status.stepsRemaining, type: .steps)
                }

                goalStatusIcon(isCompleted: isGoalCompleted, waivedToday: stepsWaived)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(healthKit.todaySteps)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())

                Text("/ \(healthKit.targetSteps) steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.vertical, Spacing.cardPadding)
    }

    // MARK: - 2. Gym Card

    private var gymCard: some View {
        VStack(alignment: .leading, spacing: Spacing.row) {
            gymHeaderRow
            gymActionButton
        }
        .padding(.vertical, Spacing.cardPadding)
    }

    /// Plain location fact, shown as a caption under the check-in/check-out
    /// button. The button's own label and enabled state already say what to
    /// do about it, so this just states where you are.
    @ViewBuilder
    private var gymGuidanceLabel: some View {
        if gymTracker.isInsideGeofence {
            gymGuidanceRow(icon: "location.fill", text: "Inside gym zone")
        } else if gymTracker.distanceToGym != nil {
            gymGuidanceRow(icon: "location", text: formattedDistance)
        } else {
            gymGuidanceRow(icon: "location.slash", text: "Location unknown")
        }
    }

    private func gymGuidanceRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.micro) {
            Image(systemName: icon)
            Text(text)
        }
    }

    private var formattedDistance: String {
        guard let distance = gymTracker.distanceToGym else { return "" }
        return distance >= 1000
            ? String(format: "%.1f km away", distance / 1000)
            : String(format: "%.0f m away", distance)
    }

    @ViewBuilder
    private var gymHeaderRow: some View {
        let isGoalCompleted = gymTracker.isGymSessionCompleted
        HStack {
            Label("Workout", systemImage: "dumbbell.fill")
                .font(.subheadline)
                .bold()

            Spacer()

            let gymWaived = network.waiveOffStatus?.gymWaivedToday ?? false

            if !isGoalCompleted, !gymWaived, let status = network.waiveOffStatus {
                waiveOffBadge(remaining: status.gymRemaining, type: .gym)
            }

            goalStatusIcon(isCompleted: isGoalCompleted, waivedToday: gymWaived)
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

                VStack(spacing: Spacing.group) {
                    Button {
                        gymTracker.checkOut()
                    } label: {
                        HStack(spacing: Spacing.iconText) {
                            Image(systemName: canCheckOut ? "figure.walk.departure" : "timer")
                            Text(canCheckOut ? "Check Out" : timeString(from: remaining))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: checkButtonsHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(readyToCheckOut ? .red : (canCheckOut ? .gray : .green))
                    .disabled(!readyToCheckOut)

                    gymGuidanceLabel
                        .font(.caption2)
                        .foregroundStyle(gymTracker.isInsideGeofence ? .green : .secondary)
                }
            }
        } else if gymTracker.hasCheckedOutToday {
            VStack(spacing: Spacing.group) {
                Button {} label: {
                    HStack(spacing: Spacing.iconText) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Session complete")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: checkButtonsHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray.opacity(0.3))
                .foregroundStyle(.green)
                .allowsHitTesting(false)

                Text(workoutDurationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: Spacing.group) {
                Button {
                    gymTracker.checkIn()
                } label: {
                    HStack(spacing: Spacing.iconText) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text("Check In")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: checkButtonsHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!gymTracker.isInsideGeofence)

                gymGuidanceLabel
                    .font(.caption2)
                    .foregroundStyle(gymTracker.isInsideGeofence ? .green : .secondary)
            }
        }
    }

    private var workoutDurationText: String {
        guard let inTime = gymTracker.lastCheckInDate, let outTime = gymTracker.lastCheckOutDate else {
            return "Workout logged for today"
        }
        let minutes = Int(outTime.timeIntervalSince(inTime) / 60)
        return "Workout duration: \(minutes) mins"
    }

    // MARK: - 3. LeetCode Card

    private var leetCodeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.row) {
            leetCodeHeaderRow
            leetCodeCountRow

            Text("Difficulty Breakdown")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            leetCodeDifficultyBreakdown
        }
        .padding(.vertical, Spacing.cardPadding)
    }

    @ViewBuilder
    private var leetCodeHeaderRow: some View {
        let isGoalCompleted = leetCode.isGoalMet
        HStack {
            Label("LeetCode", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.subheadline)
                .bold()

            Spacer()

            let leetcodeWaived = network.waiveOffStatus?.leetcodeWaivedToday ?? false

            if !isGoalCompleted, !leetcodeWaived, let status = network.waiveOffStatus {
                waiveOffBadge(remaining: status.leetcodeRemaining, type: .leetcode)
            }

            if leetCode.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                goalStatusIcon(isCompleted: isGoalCompleted, waivedToday: leetcodeWaived)
            }
        }
    }

    private var leetCodeCountRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(leetCode.totalTodayCount)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text("/ \(leetCode.targetProblems) problems")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var leetCodeDifficultyBreakdown: some View {
        HStack {
            leetCodeDifficultyColumn(label: "EASY", count: leetCode.easyTodayCount, color: .green)

            Divider()
                .frame(height: 20)

            leetCodeDifficultyColumn(label: "MEDIUM", count: leetCode.mediumTodayCount, color: .orange)

            Divider()
                .frame(height: 20)

            leetCodeDifficultyColumn(label: "HARD", count: leetCode.hardTodayCount, color: .red)
        }
    }

    private func leetCodeDifficultyColumn(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: Spacing.micro) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Device Status Card

    private var deviceStatusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.row) {
            HStack {
                Label("Internet Access", systemImage: "wifi")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Image(systemName: gateIconName)
                    .font(.title3)
                    .foregroundStyle(internetStatus.color)
            }

            HStack(spacing: Spacing.iconText) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text("Gate Controller")
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text(statusLabel)
                    .foregroundStyle(statusColor)
                    .fontWeight(.medium)
            }
            .font(.caption)

            deviceStatusFooter
        }
        .padding(.vertical, Spacing.cardPadding)
    }

    @ViewBuilder
    private var deviceStatusFooter: some View {
        if let message = networkErrorMessage {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if let lastChecked = network.lastCheckedAt {
            HStack {
                Text("Last Verified")
                Spacer()
                Text(lastChecked.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Waive-off Alert Message

    /// Percent complete (0–100, clamped) for a given goal type, based on the
    /// same live values already shown on each card.
    private func waiveOffProgressPercent(for type: NetworkManager.WaiveOffType) -> Int {
        let fraction: Double
        switch type {
        case .steps:
            fraction = healthKit.targetSteps > 0
                ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps)
                : 0
        case .gym:
            fraction = gymTracker.targetGymDurationSeconds > 0
                ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds
                : 0
        case .leetcode:
            fraction = leetCode.targetProblems > 0
                ? Double(leetCode.totalTodayCount) / Double(leetCode.targetProblems)
                : 0
        }
        return min(max(Int((fraction * 100).rounded(.down)), 0), 100)
    }

    /// Builds the confirmation message for the "Use a waive-off?" alert.
    /// Leads with a progress callout — only when the goal is already at
    /// least halfway done — followed by the standard cost-of-claiming line.
    private func waiveOffAlertMessage(for type: NetworkManager.WaiveOffType?) -> String {
        let baseMessage = "This uses one of your limited weekly waive-off cards for today."
        guard let type else { return baseMessage }

        let percent = waiveOffProgressPercent(for: type)
        guard percent >= 50 else { return baseMessage }

        return "You're already \(percent)% of the way there — you may not need it. \(baseMessage)"
    }

    // MARK: - Waive-off Badge

    /// Ticket button used to *spend* a waive-off. Only ever shown when the goal
    /// is still open and hasn't been waived yet — the "already waived" case is
    /// now handled entirely by `goalStatusIcon` so we don't double up indicators.
    @ViewBuilder
    private func waiveOffBadge(remaining: Int, type: NetworkManager.WaiveOffType) -> some View {
        Button {
            waiveOffAlertType = type
        } label: {
            HStack(spacing: Spacing.micro) {
                Image(systemName: "ticket.fill")
                Text("\(remaining) left")
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((remaining > 0 ? Color.blue : Color.gray).opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(remaining <= 0)
        .foregroundStyle(remaining > 0 ? .blue : .secondary)
    }

    /// Single trailing status glyph for a goal card. Collapses "completed" and
    /// "waived" into one indicator instead of showing a seal badge next to an
    /// unrelated empty circle.
    @ViewBuilder
    private func goalStatusIcon(isCompleted: Bool, waivedToday: Bool) -> some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else if waivedToday {
            Image(systemName: "checkmark.seal")
                .font(.title3)
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Derived Status

    /// Single source of truth for the error line under Device Status.
    /// Every network path — gate sync, waive-off fetch, LeetCode fetch —
    /// funnels through here so there's one place, one message, one color.
    private var networkErrorMessage: String? {
        if !lastSyncStatus.isEmpty { return lastSyncStatus }
        if network.waiveOffStatus == nil, let waiveOffError = network.waiveOffFetchError {
            return waiveOffError
        }
        if let leetCodeError = leetCode.errorMessage { return leetCodeError }
        return nil
    }

    private var statusColor: Color {
        switch network.connectionStatus {
        case .online: .green
        case .offline: .red
        case .unknown: .orange
        }
    }

    private var statusLabel: String {
        switch network.connectionStatus {
        case .online: "Online"
        case .offline: "Offline"
        case .unknown: "Checking…"
        }
    }

    private var internetStatus: (label: String, color: Color) {
        switch network.isGateOpen {
        case .some(true): ("Full Access", .green)
        case .some(false): ("Restricted", .red)
        case .none: ("Unknown", .orange)
        }
    }

    private var gateIconName: String {
        switch network.isGateOpen {
        case .some(true): "lock.open.fill"
        case .some(false): "lock.fill"
        case .none: "questionmark.circle.fill"
        }
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Sync

    private func refresh() async {
        lastSyncStatus = ""

        do {
            // 1. Refresh location so isInsideGeofence reflects the current position
            gymTracker.refreshLocation()

            // 2. Check the gate controller's online status via GET /status
            await network.checkStatus()

            // 3. Fetch local metrics
            await healthKit.syncSteps()
            let steps = healthKit.todaySteps

            gymTracker.checkDailyCheckoutStatus()
            gymTracker.loadTodayAccumulatedTime()
            let gymSeconds = Int(gymTracker.totalSecondsToday)

            await leetCode.fetchTodaySolvedProblems()

            // 4. Send metrics to update Internet Access status via POST /sync
            try await NetworkManager.shared.sendSync(
                steps: steps,
                gymSeconds: gymSeconds,
                leetCodeSolved: leetCode.totalTodayCount
            )

            // 5. Refresh waive-off balances (in case the ESP32 rolled over a new week)
            await network.fetchWaiveOffStatus()
//            print("waiveOffStatus:", network.waiveOffStatus as Any)
//            print("waiveOffFetchError:", network.waiveOffFetchError as Any)
        } catch {
            lastSyncStatus = "Couldn't reach your gate device — \(error.localizedDescription)"
        }
    }
}
