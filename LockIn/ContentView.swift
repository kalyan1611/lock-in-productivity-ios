import SwiftUI

struct ContentView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var network = NetworkManager.shared
    @StateObject private var gymTracker = GymTracker.shared
    
    @State private var lastSyncStatus: String = "Pull down to refresh"
    @State private var isSyncing = false
    
    @AppStorage("esp32BaseURL")
    private var esp32BaseURL: String = "http://192.168.1.14"
    
    // MARK: - Step Progress
    
    private var stepProgress: Double {
        guard healthKit.targetSteps > 0 else {
            return 0
        }
        
        return min(
            Double(healthKit.todaySteps) /
            Double(healthKit.targetSteps),
            1.0
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        
        NavigationStack {
            
            Form {
                
                // MARK: - 1. Daily Movement Card
                
                Section("Daily Movement") {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        
                        // Header Row
                        HStack {
                            
                            Label(
                                "Steps Goal",
                                systemImage: "figure.walk"
                            )
                            .font(.subheadline)
                            .bold()
                            
                            Spacer()
                            
                            Image(
                                systemName:
                                    stepProgress >= 1.0
                                ? "checkmark.circle.fill"
                                : "lock.fill"
                            )
                            .foregroundStyle(
                                stepProgress >= 1.0
                                ? .green
                                : .red
                            )
                        }
                        
                        // Big Metric Display
                        HStack(
                            alignment: .firstTextBaseline
                        ) {
                            
                            Text("\(healthKit.todaySteps)")
                                .font(
                                    .system(
                                        size: 36,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .contentTransition(
                                    .numericText()
                                )
                            
                            Text(
                                "/ \(healthKit.targetSteps) steps"
                            )
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text(
                                "\(Int(stepProgress * 100))%"
                            )
                            .font(.title3)
                            .bold()
                            .foregroundStyle(
                                stepProgress >= 1.0
                                ? .green
                                : .blue
                            )
                        }
                        
                        // Progress Bar
                        ProgressView(value: stepProgress)
                            .tint(
                                stepProgress >= 1.0
                                ? .green
                                : .blue
                            )
                        
                        // Secondary Stats
                        HStack {
                            
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                
                                Text("EST. DISTANCE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)
                                
                                Text(
                                    String(
                                        format: "%.1f km",
                                        Double(
                                            healthKit.todaySteps
                                        ) * 0.00078
                                    )
                                )
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            Divider()
                                .frame(height: 24)
                            
                            Spacer()
                            
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                
                                Text("EST. BURN")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)
                                
                                Text(
                                    "\(Int(Double(healthKit.todaySteps) * 0.04)) kcal"
                                )
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            Divider()
                                .frame(height: 24)
                            
                            Spacer()
                            
                            VStack(
                                alignment: .trailing,
                                spacing: 2
                            ) {
                                
                                Text("STATUS")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.tertiary)
                                
                                Text(
                                    stepProgress >= 1.0
                                    ? "Completed"
                                    : "In Progress"
                                )
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    stepProgress >= 1.0
                                    ? .green
                                    : .orange
                                )
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - 2. Gym Attendance Card
                
                Section("Gym Attendance") {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        
                        // Header
                        HStack {
                            Label(
                                "Time spent",
                                systemImage: "dumbbell.fill"
                            )
                            .font(.subheadline)
                            .bold()
                            
                            Spacer()
                            
                            if gymTracker.isCheckedIn,
                               let checkInDate = gymTracker.checkInDate {
                                
                                TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                                    
                                    let elapsed =
                                    context.date.timeIntervalSince(checkInDate)
                                    
                                    let remaining =
                                    max(
                                        gymTracker.targetGymDurationSeconds - elapsed,
                                        0
                                    )
                                    
                                    HStack(spacing: 6) {
                                        
                                        Image(systemName: "timer")
                                        
                                        Text(
                                            remaining > 0
                                            ? timeString(from: remaining)
                                            : "\(gymTracker.targetGymDurationMinutes):00"
                                        )
                                        .monospacedDigit()
                                        .fontWeight(.bold)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Color.green.opacity(0.12)
                                    )
                                    .clipShape(Capsule())
                                }
                                
                            } else {
                                
                                Image(
                                    systemName:
                                        gymTracker.isGateUnlocked
                                    ? "checkmark.circle.fill"
                                    : "lock.fill"
                                )
                                .foregroundStyle(
                                    gymTracker.isGateUnlocked
                                    ? .green
                                    : .red
                                )
                            }
                        }
                        
                        // Progress
                        ProgressView(
                            value: min(
                                gymTracker.totalSecondsToday /
                                gymTracker.targetGymDurationSeconds,
                                1.0
                            )
                        )
                        .tint(
                            gymTracker.isGateUnlocked
                            ? .green
                            : .orange
                        )
                        
                        // Location / accumulated time
                        HStack {
                            
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                
                                Text(
                                    gymTracker.isInsideGeofence
                                    ? "Inside Gym 📍"
                                    : "Outside Gym"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    gymTracker.isInsideGeofence
                                    ? .green
                                    : .secondary
                                )
                                
                            }
                            
                            Spacer()
                            
                            Text(
                                "\(Int(gymTracker.totalSecondsToday / 60))/\(gymTracker.targetGymDurationMinutes) mins"
                            )
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)
                        }
                        
                        // MARK: Check In / Check Out
                        
                        HStack(spacing: 12) {
                            
                            // CHECK IN
                            VStack(spacing: 6) {
                                
                                Button {
                                    
                                    gymTracker.checkIn()
                                    
                                } label: {
                                    
                                    VStack(spacing: 6) {
                                        
                                        Image(
                                            systemName:
                                                "figure.strengthtraining.traditional"
                                        )
                                        .font(.system(size: 20, weight: .semibold))
                                        
                                        Text("Check In")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(
                                        maxWidth: .infinity
                                    )
                                    .frame(height: 65)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                                .disabled(
                                    !gymTracker.isInsideGeofence ||
                                    gymTracker.isCheckedIn ||
                                    gymTracker.hasCheckedOutToday
                                )
                                
                                if let checkInDate = gymTracker.checkInDate {
                                    
                                    Text(
                                        "Checked in at " +
                                        checkInDate.formatted(
                                            date: .omitted,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    
                                } else if gymTracker.hasCheckedOutToday,
                                          let lastCheckInDate = gymTracker.lastCheckInDate {
                                    
                                    Text(
                                        "Checked in at " +
                                        lastCheckInDate.formatted(
                                            date: .omitted,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    
                                } else {
                                    
                                    Text(
                                        gymTracker.isInsideGeofence
                                        ? "Ready to check in"
                                        : "Enter gym zone first"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            // CHECK OUT
                            VStack(spacing: 6) {
                                
                                if gymTracker.isCheckedIn,
                                   let checkInDate = gymTracker.checkInDate {
                                    
                                    TimelineView(
                                        .periodic(
                                            from: checkInDate,
                                            by: 1
                                        )
                                    ) { context in
                                        
                                        let elapsed =
                                        context.date.timeIntervalSince(
                                            checkInDate
                                        )
                                        
                                        let canCheckOut =
                                        elapsed >= gymTracker.targetGymDurationSeconds
                                        
                                        Button {
                                            
                                            gymTracker.checkOut()
                                            
                                        } label: {
                                            
                                            VStack(spacing: 6) {
                                                
                                                Image(
                                                    systemName:
                                                        "figure.walk.departure"
                                                )
                                                .font(
                                                    .system(
                                                        size: 20,
                                                        weight: .semibold
                                                    )
                                                )
                                                
                                                Text("Check Out")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                            .frame(
                                                maxWidth: .infinity
                                            )
                                            .frame(height: 65)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .disabled(!canCheckOut)
                                        
                                        if canCheckOut {
                                            
                                            Text("Ready to check out")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                            
                                        } else {
                                            
                                            Text(
                                                "Available in " +
                                                timeString(
                                                    from:
                                                        max(
                                                            gymTracker.targetGymDurationSeconds - elapsed,
                                                            0
                                                        )
                                                )
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                        }
                                    }
                                    
                                } else if gymTracker.hasCheckedOutToday {
                                    
                                    Button {
                                        // No-op: already checked out for today
                                    } label: {
                                        
                                        VStack(spacing: 6) {
                                            
                                            Image(
                                                systemName:
                                                    "figure.walk.departure"
                                            )
                                            .font(
                                                .system(
                                                    size: 20,
                                                    weight: .semibold
                                                )
                                            )
                                            
                                            Text("Checked Out")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .frame(
                                            maxWidth: .infinity
                                        )
                                        .frame(height: 65)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.gray)
                                    .disabled(true)
                                    
                                    if let lastCheckOutDate = gymTracker.lastCheckOutDate {
                                        
                                        Text(
                                            "Checked out at " +
                                            lastCheckOutDate.formatted(
                                                date: .omitted,
                                                time: .shortened
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        
                                    } else {
                                        
                                        Text("Done for today")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                } else {
                                    
                                    Button {
                                        
                                        gymTracker.checkOut()
                                        
                                    } label: {
                                        
                                        VStack(spacing: 6) {
                                            
                                            Image(
                                                systemName:
                                                    "figure.walk.departure"
                                            )
                                            .font(
                                                .system(
                                                    size: 20,
                                                    weight: .semibold
                                                )
                                            )
                                            
                                            Text("Check Out")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .frame(
                                            maxWidth: .infinity
                                        )
                                        .frame(height: 65)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .disabled(true)
                                    
                                    Text("Check in first")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - 3. Hardware Hub
                
                Section("Control Hub") {
                    
                    HStack {
                        
                        Label {
                            
                            Text("Lock Controller")
                            
                        } icon: {
                            
                            Image(systemName: "cpu")
                                .foregroundStyle(.blue)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            
                            Circle()
                                .fill(statusColor)
                                .frame(
                                    width: 8,
                                    height: 8
                                )
                            
                            Text(statusLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            statusColor.opacity(0.12)
                        )
                        .clipShape(Capsule())
                    }
                    
                    HStack {
                        
                        Label {
                            
                            Text("Internet Access")
                            
                        } icon: {
                            
                            Image(
                                systemName:
                                    network.goalMet == true
                                ? "lock.open.fill"
                                : "lock.fill"
                            )
                            .foregroundStyle(
                                network.goalMet == true
                                ? .green
                                : .orange
                            )
                        }
                        
                        Spacer()
                        
                        Text(internetStatusLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                network.goalMet == true
                                ? .green
                                : .secondary
                            )
                    }
                    
                    if !lastSyncStatus.isEmpty {
                        
                        Text(lastSyncStatus)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                    } else if let lastChecked = network.lastCheckedAt {
                        
                        HStack {
                            Text("Last Verified")
                            Spacer()
                            Text(
                                lastChecked.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            
            .navigationTitle("LockIn")
            .navigationBarTitleDisplayMode(.inline)
            
            // MARK: - Pull To Refresh
            
            .refreshable {
                await syncNow()
            }
        }
        
        .onAppear {
            gymTracker.requestLocationPermissionIfNeeded()
        }
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        
        switch network.connectionStatus {
            
        case .online:
            return .green
            
        case .offline:
            return .red
            
        case .unknown:
            return .orange
        }
    }
    
    private var statusLabel: String {
        
        switch network.connectionStatus {
            
        case .online:
            return "Online"
            
        case .offline:
            return "Offline"
            
        case .unknown:
            return "Checking…"
        }
    }
    
    private var internetStatusLabel: String {
        
        let stalePrefix =
        network.connectionStatus == .offline
        ? "(last) "
        : ""
        
        switch network.goalMet {
            
        case .some(true):
            return stalePrefix + "Granted"
            
        case .some(false):
            return stalePrefix + "Restricted"
            
        case .none:
            return "Unknown"
        }
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let seconds = total % 60
        
        return String(
            format: "%02d:%02d",
            minutes,
            seconds
        )
    }
    
    private func elapsedText(from start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        
        return "Time spent: " + timeString(from: elapsed)
    }
    
    // MARK: - Sync
    
    private func syncNow() async {
        
        isSyncing = true
        lastSyncStatus = ""
        
        defer {
            isSyncing = false
        }
        
        do {
            
            // Refresh location so isInsideGeofence reflects the current position
            gymTracker.refreshLocation()
            
            // Fetch today's HealthKit steps
            let steps =
            try await healthKit.fetchTodaySteps()
            
            healthKit.todaySteps = steps
            
            // Refresh today's gym time
            gymTracker.loadTodayAccumulatedTime()
            
            let gymSeconds =
            Int(gymTracker.totalSecondsToday)
            
            // Send everything to ESP32
            try await NetworkManager.shared.sendSync(
                steps: steps,
                gymSeconds: gymSeconds
            )
            
        } catch {
            lastSyncStatus =
            "Sync failed: \(error.localizedDescription)"
        }
    }
}
