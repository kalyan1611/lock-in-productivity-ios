import SwiftUI
import MapKit

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
                        
                        if !lastSyncStatus.isEmpty {
                            
                            Text(lastSyncStatus)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - 2. Gym Attendance Card
                
                Section("Gym Attendance") {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        
                        HStack {
                            
                            Label(
                                "Time spent",
                                systemImage: "dumbbell.fill"
                            )
                            .font(.subheadline)
                            .bold()
                            
                            Spacer()
                            
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
                        
                        // Gym Progress
                        ProgressView(
                            value: min(
                                gymTracker.totalSecondsToday /
                                (45 * 60),
                                1.0
                            )
                        )
                        .tint(
                            gymTracker.isGateUnlocked
                            ? .green
                            : .orange
                        )
                        
                        HStack {
                            
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                
                                Text(
                                    gymTracker.isCurrentlyAtGym
                                    ? "Zone Verified 📍"
                                    : "Out of Range"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    gymTracker.isCurrentlyAtGym
                                    ? .green
                                    : .secondary
                                )
                                
                                // Live Distance
                                if let distance =
                                    gymTracker.distanceFromGymMeters {
                                    
                                    Text(
                                        distance >= 1000
                                        ? String(
                                            format:
                                                "Distance: %.2f km",
                                            distance / 1000
                                        )
                                        : String(
                                            format:
                                                "Distance: %.0f m",
                                            distance
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }
                            
                            Spacer()
                            
                            Text(
                                "\(Int(gymTracker.totalSecondsToday / 60))/45 mins"
                            )
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)
                        }
                        
                        // Gym Map
                        Map(
                            position: .constant(
                                .region(
                                    MKCoordinateRegion(
                                        center:
                                            gymTracker.gymCoordinate,
                                        span:
                                            MKCoordinateSpan(
                                                latitudeDelta: 0.005,
                                                longitudeDelta: 0.005
                                            )
                                    )
                                )
                            )
                        ) {
                            
                            Marker(
                                "Gym Zone",
                                coordinate:
                                    gymTracker.gymCoordinate
                            )
                            .tint(.red)
                            
                            MapCircle(
                                center:
                                    gymTracker.gymCoordinate,
                                radius: 40
                            )
                            .foregroundStyle(
                                Color.red.opacity(0.15)
                            )
                            .stroke(
                                .red,
                                lineWidth: 1
                            )
                        }
                        .frame(height: 100)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 8
                            )
                        )
                        .disabled(true)
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
                    
                    if let lastChecked =
                        network.lastCheckedAt {
                        
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
        
        // MARK: - Foreground / Background Location
        
        .onAppear {
            gymTracker.requestLocationPermissionIfNeeded()
            gymTracker.startForegroundLocationUpdates()
        }
        
        .onChange(of: scenePhase) { _, newPhase in
            
            switch newPhase {
                
            case .active:
                gymTracker.startForegroundLocationUpdates()
                
            case .inactive, .background:
                gymTracker.stopForegroundLocationUpdates()
                
            @unknown default:
                break
            }
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
    
    // MARK: - Sync
    
    private func syncNow() async {
        
        isSyncing = true
        
        defer {
            isSyncing = false
        }
        
        do {
            
            // Fetch today's HealthKit steps
            let steps =
            try await healthKit.fetchTodaySteps()
            
            healthKit.todaySteps = steps
            
            // Refresh today's gym time
            gymTracker.loadTodayAccumulatedTime()
            
            let gymSeconds =
            Int(gymTracker.totalSecondsToday)
            
            // Send everything to ESP32
            let result =
            try await NetworkManager.shared.sendSync(
                steps: steps,
                gymSeconds: gymSeconds
            )
            
            let goalText =
            result.goalMet
            ? "Access Granted ✅"
            : "Access Restricted 🔒"
            
            lastSyncStatus =
            "Updated \(Date().formatted(date: .omitted, time: .shortened)) — \(goalText)"
            
        } catch {
            
            lastSyncStatus =
            "Sync failed: \(error.localizedDescription)"
        }
    }
}
