import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared

    @State private var lastSyncStatus: String = ""
    @State private var showingQRScanner = false
    @State private var isCheckingOut = false

    private var checkButtonsHeight: CGFloat = 38
    private var gymQR = AppConfig.Gym.expectedQRCode

    private var stepProgress: Double {
        guard healthKit.targetSteps > 0 else { return 0 }
        return min(Double(healthKit.todaySteps) / Double(healthKit.targetSteps), 1.0)
    }

    private var gymStatusText: String {
        if gymTracker.isCheckedIn {
            return "Session in Progress"
        } else if gymTracker.hasCheckedOutToday {
            return "Session Completed"
        } else {
            return "Not Checked In"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. Daily Movement Card

                Section("Steps") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Today's Steps", systemImage: "figure.walk")
                                .font(.subheadline)
                                .bold()

                            Spacer()

                            Image(systemName: stepProgress >= 1.0 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(stepProgress >= 1.0 ? .green : .secondary)
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

                // MARK: - 2. Gym Attendance Card

                Section("Gym Session") {
                    VStack(alignment: .leading, spacing: 8) {
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
                                Image(systemName: gymTracker.isGateUnlocked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(gymTracker.isGateUnlocked ? .green : .secondary)
                            }
                        }

                        HStack {
                            if !gymTracker.hasCheckedOutToday {
                                Text(gymStatusText)
                                    .font(.caption)
                                    .foregroundStyle(gymTracker.isCheckedIn ? .green : .secondary)

                                Spacer()

                                Text("\(Int(gymTracker.totalSecondsToday / 60))/\(gymTracker.targetGymDurationMinutes) mins")
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        gymActionButton
                    }
                    .padding(.vertical, 2)
                }

                // MARK: - 3. LeetCode Session Card

                Section("LeetCode") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Today's submissions", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.subheadline)
                                .bold()

                            Spacer()

                            if leetCode.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: leetCode.isGoalMet ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(leetCode.isGoalMet ? .green : .secondary)
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("\(leetCode.totalTodayCount)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())

                            Text("/ \(leetCode.targetProblems) problems")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }

                        Text("Difficulty Breakdown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        HStack {
                            VStack(spacing: 2) {
                                Text("EASY")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)

                                Text("\(leetCode.easyTodayCount)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 20)

                            VStack(spacing: 2) {
                                Text("MEDIUM")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)

                                Text("\(leetCode.mediumTodayCount)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 20)

                            VStack(spacing: 2) {
                                Text("HARD")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)

                                Text("\(leetCode.hardTodayCount)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // MARK: - 4. Control Hub Card

                Section("Device Status") {
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

                        if !lastSyncStatus.isEmpty {
                            Text(lastSyncStatus)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    .padding(.vertical, 2)
                }
            }
            .listSectionSpacing(.compact)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await leetCode.fetchTodaySolvedProblems()
                await network.checkStatus()
            }
            .refreshable {
                await syncNow()
            }
            .sheet(isPresented: $showingQRScanner) {
                QRCodeScannerView(expectedCode: gymQR) {
                    if isCheckingOut {
                        gymTracker.checkOut()
                    } else {
                        gymTracker.checkIn()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(checkInDate)
                let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds

                VStack(spacing: 4) {
                    Button {
                        isCheckingOut = true
                        showingQRScanner = true
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
                    .tint(canCheckOut ? .red : .gray)
                    .disabled(!canCheckOut)

                    Text(canCheckOut ? "Target reached • Ready to check out" : "Minimum duration required")
                        .font(.caption2)
                        .foregroundStyle(canCheckOut ? .green : .secondary)
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
                    isCheckingOut = false
                    showingQRScanner = true
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

                Text("Scan QR code to start session")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch network.connectionStatus {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .orange
        }
    }

    private var statusLabel: String {
        switch network.connectionStatus {
        case .online: return "Online"
        case .offline: return "Offline"
        case .unknown: return "Checking…"
        }
    }

    private var internetStatus: (label: String, color: Color) {
        switch network.isGateOpen {
        case .some(true): return ("Full Access", .green)
        case .some(false): return ("Restricted", .red)
        case .none: return ("Unknown", .orange)
        }
    }

    private var gateIconName: String {
        switch network.isGateOpen {
        case .some(true): return "lock.open.fill"
        case .some(false): return "lock.fill"
        case .none: return "questionmark.circle.fill"
        }
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func syncNow() async {
        lastSyncStatus = ""

        do {
            // 1. Check the gate controller's online status via GET /status
            await network.checkStatus()

            // 2. Fetch local metrics
            let steps = try await healthKit.fetchTodaySteps()
            healthKit.todaySteps = steps

            gymTracker.loadTodayAccumulatedTime()
            let gymSeconds = Int(gymTracker.totalSecondsToday)

            await leetCode.fetchTodaySolvedProblems()

            // 3. Send metrics to update Internet Access status via POST /sync
            try await NetworkManager.shared.sendSync(
                steps: steps,
                gymSeconds: gymSeconds,
                leetCodeSolved: leetCode.totalTodayCount
            )
        } catch {
            lastSyncStatus = "Couldn't reach your gate device — \(error.localizedDescription)"
        }
    }
}
