import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared

    @State private var lastSyncStatus: String = ""

    // MARK: - Waive-off UI state

    @State private var waiveOffAlertType: NetworkManager.WaiveOffType?
    @State private var waiveOffError: String?

    private var checkButtonsHeight: CGFloat = 38

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Steps") { stepsCard }
                Section("Gym Session") { gymCard }
                Section("LeetCode") { leetCodeCard }
                Section("Device Status") { deviceStatusCard }
            }
            .listSectionSpacing(.compact)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await leetCode.fetchTodaySolvedProblems()
                await network.checkStatus()
                await network.fetchWaiveOffStatus()
            }
            .refreshable {
                await syncNow()
            }
            .onAppear {
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
                Button("Confirm", role: .destructive) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today's Steps", systemImage: "figure.walk")
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
        .padding(.vertical, 2)
    }

    // MARK: - 2. Gym Card

    private var gymCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            gymHeaderRow
            gymStatusRow
            gymActionButton
        }
        .padding(.vertical, 2)
    }

    private var gymStatusRow: some View {
        HStack(spacing: 6) {
            locationLabel
                .foregroundStyle(gymTracker.isInsideGeofence ? .green : .secondary)

            Spacer()

            if !gymTracker.hasCheckedOutToday {
                let minutesToday = Int(gymTracker.totalSecondsToday / 60)
                let targetMinutes = gymTracker.targetGymDurationMinutes

                Text("\(minutesToday)/\(targetMinutes) mins")
                    .bold()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var locationLabel: some View {
        if gymTracker.isInsideGeofence {
            Label("Inside gym zone", systemImage: "location.fill")
        } else if let distance = gymTracker.distanceToGym {
            let formattedDistance = distance >= 1000
                ? String(format: "%.1f km away", distance / 1000)
                : String(format: "%.0f m away", distance)

            Label(formattedDistance, systemImage: "location")
        } else {
            Label("Location unknown", systemImage: "location.slash")
        }
    }

    @ViewBuilder
    private var gymHeaderRow: some View {
        let isGoalCompleted = gymTracker.isGymSessionCompleted
        HStack {
            Label("Session Time", systemImage: "dumbbell.fill")
                .font(.subheadline)
                .bold()

            Spacer()

            if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
                TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(checkInDate)
                    let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)

                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(remaining > 0 ? timeString(from: remaining) : "\(gymTracker.targetGymDurationMinutes):00")
                            .monospacedDigit()
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }
            } else {
                let gymWaived = network.waiveOffStatus?.gymWaivedToday ?? false

                if !isGoalCompleted, !gymWaived, let status = network.waiveOffStatus {
                    waiveOffBadge(remaining: status.gymRemaining, type: .gym)
                }

                goalStatusIcon(isCompleted: isGoalCompleted, waivedToday: gymWaived)
            }
        }
    }

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(checkInDate)
                let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds

                let readyToCheckOut = canCheckOut && gymTracker.isInsideGeofence

                VStack(spacing: 4) {
                    Button {
                        gymTracker.checkOut()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk.departure")
                            Text("Check Out")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: checkButtonsHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(readyToCheckOut ? .red : .gray)
                    .disabled(!readyToCheckOut)

                    Text(
                        !canCheckOut
                            ? "Minimum duration required"
                            : gymTracker.isInsideGeofence
                            ? "Target reached • Ready to check out"
                            : "Return to gym zone to check out"
                    )
                    .font(.caption2)
                    .foregroundStyle(readyToCheckOut ? .green : .secondary)
                }
            }
        } else if gymTracker.hasCheckedOutToday {
            VStack(spacing: 4) {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Session Complete")
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

                if let inTime = gymTracker.lastCheckInDate?.formatted(date: .omitted, time: .shortened),
                   let outTime = gymTracker.lastCheckOutDate?.formatted(date: .omitted, time: .shortened)
                {
                    Text("In at \(inTime) • Out at \(outTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Workout logged for today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 4) {
                Button {
                    gymTracker.checkIn()
                } label: {
                    HStack(spacing: 6) {
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

                Text(gymTracker.isInsideGeofence ? "Ready to check in" : "Enter gym zone to check in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 3. LeetCode Card

    private var leetCodeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            leetCodeHeaderRow
            leetCodeCountRow

            Text("Difficulty Breakdown")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            leetCodeDifficultyBreakdown
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var leetCodeHeaderRow: some View {
        let isGoalCompleted = leetCode.isGoalMet
        HStack {
            Label("Today's submissions", systemImage: "chevron.left.forwardslash.chevron.right")
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
        VStack(spacing: 2) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Internet Access", systemImage: "wifi")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Image(systemName: gateIconName)
                    .font(.title3)
                    .foregroundStyle(internetStatus.color)
            }

            HStack(spacing: 6) {
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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var deviceStatusFooter: some View {
        if !lastSyncStatus.isEmpty {
            Text(lastSyncStatus)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if network.waiveOffStatus == nil, let waiveOffError = network.waiveOffFetchError {
            Text(waiveOffError)
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
            HStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                Text("\(remaining)")
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

    private func syncNow() async {
        lastSyncStatus = ""

        do {
            // 1. Refresh location so isInsideGeofence reflects the current position
            gymTracker.refreshLocation()

            // 2. Check the gate controller's online status via GET /status
            await network.checkStatus()

            // 3. Fetch local metrics
            await healthKit.syncSteps()
            let steps = healthKit.todaySteps

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
