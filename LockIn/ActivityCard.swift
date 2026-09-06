import SwiftUI

struct ActivityCard: View {
    @Binding var selectedTab: GoalTab
    @Binding var selectedPeriod: StatsPeriod

    @ObservedObject var healthKit: HealthKitManager
    @ObservedObject var gymTracker: GymTracker
    @ObservedObject var leetCode: LeetCodeManager

    let waiveOffStatus: NetworkManager.WaiveOffStatus?
    let onTapWaiveOff: (NetworkManager.WaiveOffType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            GoalTabSwitcher(selection: $selectedTab)
                .onChange(of: selectedTab) { _, _ in selectedPeriod = .day }

            if selectedTab != .leetcode || selectedPeriod == .day {
                PeriodSwitcher(
                    selection: $selectedPeriod,
                    disabledPeriods: selectedTab == .leetcode ? [.week, .month] : []
                )
            }

            Group {
                switch selectedTab {
                case .steps: stepsContent
                case .gym: gymContent
                case .leetcode: leetCodeContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.surfaceStroke, lineWidth: 1))
    }

    // MARK: Header (title + ticket badge tied to selected tab)

    private var isCompletedForTab: Bool {
        switch selectedTab {
        case .steps: healthKit.areTodaysStepsCompleted
        case .gym: gymTracker.isGymSessionCompleted
        case .leetcode: leetCode.isGoalMet
        }
    }

    private var waivedForTab: Bool {
        switch selectedTab {
        case .steps: waiveOffStatus?.stepsWaivedToday ?? false
        case .gym: waiveOffStatus?.gymWaivedToday ?? false
        case .leetcode: waiveOffStatus?.leetcodeWaivedToday ?? false
        }
    }

    private var waiveRemainingForTab: Int? {
        switch selectedTab {
        case .steps: waiveOffStatus?.stepsRemaining
        case .gym: waiveOffStatus?.gymRemaining
        case .leetcode: waiveOffStatus?.leetcodeRemaining
        }
    }

    private var header: some View {
        HStack {
            Text("ACTIVITY")
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if !isCompletedForTab, !waivedForTab, TimeUtils.isFreeTime(), let remaining = waiveRemainingForTab {
                TicketBadge(remaining: remaining) {
                    onTapWaiveOff(selectedTab.waiveOffType)
                }
            }
        }
    }

    // MARK: Steps

    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedPeriod == .day {
                todayStat(
                    value: "\(healthKit.todaySteps)",
                    unit: "of \(healthKit.targetSteps) steps",
                    progress: healthKit.targetSteps > 0 ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps) : 0,
                    icon: "figure.walk",
                    isCompleted: healthKit.areTodaysStepsCompleted,
                    waived: waiveOffStatus?.stepsWaivedToday ?? false
                )
                Spacer()
            } else {
                ActivityBarChart(
                    entries: healthKit.stepsHistory.map { ($0.date, Double($0.steps)) },
                    target: Double(healthKit.targetSteps),
                    period: selectedPeriod
                )
                .task(id: selectedPeriod) {
                    await healthKit.syncStepsHistory(days: selectedPeriod == .week ? 7 : 30)
                }
            }
        }
    }

    // MARK: Gym

    private var gymContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedPeriod == .day {
                todayStat(
                    value: "\(Int(gymTracker.totalSecondsToday) / 60) min",
                    unit: "of \(gymTracker.targetGymDurationMinutes) min target",
                    progress: gymTracker.targetGymDurationSeconds > 0 ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds : 0,
                    icon: "dumbbell.fill",
                    isCompleted: gymTracker.isGymSessionCompleted,
                    waived: waiveOffStatus?.gymWaivedToday ?? false
                )
                gymActionButton
                Spacer()
            } else {
                let history = gymTracker.secondsHistory(days: selectedPeriod == .week ? 7 : 30)
                ActivityBarChart(
                    entries: history.map { ($0.date, $0.seconds / 60) },
                    target: Double(gymTracker.targetGymDurationMinutes),
                    period: selectedPeriod
                )
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
                let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)

                Button {
                    gymTracker.checkOut()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: canCheckOut ? "figure.walk.departure" : "timer")
                        Text(canCheckOut ? "Check Out" : timeString(from: remaining)).monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(readyToCheckOut ? Palette.background : Palette.textSecondary)
                .background(Capsule().fill(readyToCheckOut ? Palette.open : Palette.surfaceStroke))
                .disabled(!readyToCheckOut)
            }
        } else if !gymTracker.hasCheckedOutToday {
            Button {
                gymTracker.checkIn()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("Check In")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gymTracker.isInsideGeofence ? Palette.background : Palette.textSecondary)
            .background(Capsule().fill(gymTracker.isInsideGeofence ? Palette.open : Palette.surfaceStroke))
            .disabled(!gymTracker.isInsideGeofence)
        }
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: LeetCode

    private var leetCodeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            todayStat(
                value: "\(leetCode.totalTodayCount)",
                unit: "of \(leetCode.targetProblems) problems",
                progress: leetCode.progress,
                icon: "chevron.left.forwardslash.chevron.right",
                isCompleted: leetCode.isGoalMet,
                waived: waiveOffStatus?.leetcodeWaivedToday ?? false
            )

            if selectedPeriod != .day {
                Spacer()
                Text("Week/Month history coming soon")
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
            } else {
                Spacer()
            }
        }
    }

    // MARK: Shared "today" stat block

    private func todayStat(value: String, unit: String, progress: Double, icon: String, isCompleted: Bool, waived: Bool) -> some View {
        let color = GoalColor.forProgress(progress, isCompleted: isCompleted, waived: waived)
        return HStack(spacing: 16) {
            ZStack {
                RingProgress(progress: progress, color: color, lineWidth: 7)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}