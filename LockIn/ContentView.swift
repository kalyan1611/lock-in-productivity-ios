import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var leetCode = LeetCodeManager.shared
    @ObservedObject private var gymTracker = GymTracker.shared
    
    @State private var lastSyncStatus: String = ""
    @State private var showingQRScanner = false
    @State private var isCheckingOut = false
    
    // Toggle for LeetCode breakdown
    @State private var isLeetCodeExpanded = false
    
    private var checkButtonsHeight: CGFloat = 38
    private var gymQR = "https://scan.page/Fkx8f4"
    
    // MARK: - Step Progress
    
    private var stepProgress: Double {
        guard healthKit.targetSteps > 0 else { return 0 }
        return min(Double(healthKit.todaySteps) / Double(healthKit.targetSteps), 1.0)
    }
    
    // MARK: - Gym Helper
    
    private var gymStatusText: String {
        if gymTracker.isCheckedIn {
            return "Session in Progress"
        } else if gymTracker.hasCheckedOutToday {
            return "Session Completed"
        } else {
            return "Not Checked In"
        }
    }
    
    // MARK: - Body
    
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
                            
                            Image(systemName: stepProgress >= 1.0 ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(stepProgress >= 1.0 ? .green : .red)
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
                        // Header Row
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
                                Image(systemName: gymTracker.isGateUnlocked ? "checkmark.circle.fill" : "lock.fill")
                                    .foregroundStyle(gymTracker.isGateUnlocked ? .green : .red)
                            }
                        }
                        
                        // Status Metrics
                        HStack {
                            Text(gymStatusText)
                                .font(.caption)
                                .foregroundStyle(gymTracker.isCheckedIn ? .green : .secondary)
                            
                            Spacer()
                            
                            Text("\(Int(gymTracker.totalSecondsToday / 60))/\(gymTracker.targetGymDurationMinutes) mins")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                        }
                        
                        // Single Dynamic Action Button
                        gymActionButton
                    }
                    .padding(.vertical, 2)
                }
                
                // MARK: - 3. LeetCode Session Card
                
                Section("LeetCode") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Header Row (Stationary)
                        HStack {
                            Label("Today's submissions", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.subheadline)
                                .bold()
                            
                            Spacer()
                            
                            if leetCode.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: leetCode.isGoalMet ? "checkmark.circle.fill" : "lock.fill")
                                    .foregroundStyle(leetCode.isGoalMet ? .green : .red)
                            }
                        }
                        
                        // Big Metric Display (Stationary)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(leetCode.totalTodayCount)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            
                            Text("/ \(leetCode.targetProblems) problems")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        
                        // Collapsible Header Toggle
                        Button {
                            isLeetCodeExpanded.toggle()
                        } label: {
                            HStack {
                                Text("Difficulty Breakdown")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isLeetCodeExpanded ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: isLeetCodeExpanded)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Isolated Collapsible Breakdown Content
                        Group {
                            if isLeetCodeExpanded {
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
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: isLeetCodeExpanded)
                    }
                    .padding(.vertical, 2)
                }
                
                // MARK: - 4. Hardware Hub
                
                Section("Device Status") {
                    HStack {
                        Label {
                            Text("Gate Controller")
                        } icon: {
                            Image(systemName: "cpu")
                                .foregroundStyle(.blue)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(statusLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    HStack {
                        Label {
                            Text("Internet Access")
                        } icon: {
                            Image(systemName: "wifi")
                                .foregroundStyle(.blue)
                        }
                        
                        Spacer()
                        
                        Text(internetStatus.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(internetStatus.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
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
            }
            .listSectionSpacing(.compact)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await leetCode.fetchTodaySolvedProblems()
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
    
    // MARK: - Dynamic Gym Action Button Component
    
    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(checkInDate)
                let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds
                let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)
                
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
                    
                    Text(canCheckOut ? "Target reached • Ready to check out" : "Unlocks in \(timeString(from: remaining))")
                        .font(.caption2)
                        .monospacedDigit()
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
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(true)
                
                if let inTime = gymTracker.lastCheckInDate?.formatted(date: .omitted, time: .shortened),
                   let outTime = gymTracker.lastCheckOutDate?.formatted(date: .omitted, time: .shortened) {
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
    
    // MARK: - Helpers
    
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
        switch network.goalMet {
        case .some(true): return ("Full Access", .green)
        case .some(false): return ("Restricted", .red)
        case .none: return ("Unknown", .orange)
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
            let steps = try await healthKit.fetchTodaySteps()
            healthKit.todaySteps = steps
            
            gymTracker.loadTodayAccumulatedTime()
            let gymSeconds = Int(gymTracker.totalSecondsToday)
            
            await leetCode.fetchTodaySolvedProblems()
            
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
