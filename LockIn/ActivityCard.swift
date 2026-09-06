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

            // .topLeading matters here — without an explicit alignment this
            // frame defaults to centering non-expanding content (that's why
            // today's stat was rendering centered before), pushing it away
            // from the card's top-left and leaving dead space below.
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Tab content dispatch

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .steps:
            stepsContent
        case .gym:
            gymContent
        case .leetcode:
            leetCodeContent
        }
    }

    // MARK: - Header (title + ticket badge tied to selected tab)

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

            if !isCompletedForTab,
               !waivedForTab,
               TimeUtils.isFreeTime(),
               let remaining = waiveRemainingForTab {
                TicketBadge(remaining: remaining) {
                    onTapWaiveOff(selectedTab.waiveOffType)
                }
            }
        }
    }

    // MARK: - Steps
    // Today's stat is always shown; the chart below it always reflects
    // whichever period (Week/Month) is selected and expands to fill
    // whatever vertical space remains in the card.

    @ViewBuilder
    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(healthKit.todaySteps)",
                unit: "of \(healthKit.targetSteps) steps",
                progress: healthKit.targetSteps > 0
                    ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps) : 0,
                icon: "figure.walk",
                isCompleted: healthKit.areTodaysStepsCompleted,
                waived: waiveOffStatus?.stepsWaivedToday ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            PeriodSwitcher(selection: $selectedPeriod)

            ActivityBarChart(
                entries: healthKit.stepsHistory.map { day in
                    let met = healthKit.targetSteps > 0
                        ? Double(day.steps) >= Double(healthKit.targetSteps) : false
                    return ActivityBarChart.Entry(
                        date: day.date,
                        segments: [
                            ActivityBarChart.Segment(
                                value: Double(day.steps),
                                color: met ? Palette.open : Palette.started
                            )
                        ]
                    )
                },
                target: Double(healthKit.targetSteps),
                period: selectedPeriod,
                valueLabel: { "\(Int($0))" }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: selectedPeriod) {
                await healthKit.syncStepsHistory(days: selectedPeriod == .week ? 7 : 30)
            }
        }
    }

    // MARK: - Gym

    @ViewBuilder
    private var gymContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(Int(gymTracker.totalSecondsToday) / 60) min",
                unit: "of \(gymTracker.targetGymDurationMinutes) min target",
                progress: gymTracker.targetGymDurationSeconds > 0
                    ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds : 0,
                icon: "dumbbell.fill",
                isCompleted: gymTracker.isGymSessionCompleted,
                waived: waiveOffStatus?.gymWaivedToday ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            gymActionButton
            PeriodSwitcher(selection: $selectedPeriod)

            let history = gymTracker.secondsHistory(days: selectedPeriod == .week ? 7 : 30)
            ActivityBarChart(
                entries: history.map { day in
                    let minutes = day.seconds / 60
                    let met = minutes >= Double(gymTracker.targetGymDurationMinutes)
                    return ActivityBarChart.Entry(
                        date: day.date,
                        segments: [
                            ActivityBarChart.Segment(
                                value: minutes,
                                color: met ? Palette.open : Palette.started
                            )
                        ]
                    )
                },
                target: Double(gymTracker.targetGymDurationMinutes),
                period: selectedPeriod,
                valueLabel: { "\(Int($0))m" }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            GymCountdownButton(gymTracker: gymTracker, checkInDate: checkInDate)
        } else if gymTracker.hasCheckedOutToday {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("Session complete")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.open)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Capsule().fill(Palette.open.opacity(0.12)))
        } else {
            Button {
                gymTracker.checkIn()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("Check In")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gymTracker.isInsideGeofence ? Palette.background : Palette.textSecondary)
            .background(Capsule().fill(gymTracker.isInsideGeofence ? Palette.open : Palette.surfaceStroke))
            .disabled(!gymTracker.isInsideGeofence)
        }
    }

    // MARK: - LeetCode
    // Chart is backed by locally-cached daily easy/medium/hard totals (see
    // LeetCodeManager.breakdownHistory) since the public API only exposes a
    // rolling recent-submissions list, not backdated calendar data. Bars
    // render as a stack of easy/medium/hard segments, color-matched to the
    // difficultyBreakdown row above the chart.

    @ViewBuilder
    private var leetCodeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayStat(
                value: "\(leetCode.totalTodayCount)",
                unit: "of \(leetCode.targetProblems) problems",
                progress: leetCode.progress,
                icon: "chevron.left.forwardslash.chevron.right",
                isCompleted: leetCode.isGoalMet,
                waived: waiveOffStatus?.leetcodeWaivedToday ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            difficultyBreakdown
            PeriodSwitcher(selection: $selectedPeriod)

            let breakdown = leetCode.breakdownHistory(days: selectedPeriod == .week ? 7 : 30)
            ActivityBarChart(
                entries: breakdown.map { day in
                    ActivityBarChart.Entry(
                        date: day.date,
                        segments: [
                            ActivityBarChart.Segment(value: Double(day.easy), color: Palette.open),
                            ActivityBarChart.Segment(value: Double(day.medium), color: Palette.waived),
                            ActivityBarChart.Segment(value: Double(day.hard), color: Palette.locked)
                        ]
                    )
                },
                target: Double(leetCode.targetProblems),
                period: selectedPeriod,
                valueLabel: { "\(Int($0))" }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !leetCode.hasMultiDayHistory() {
                Text("History builds day by day from today — full backdated history needs LeetCode's calendar API.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
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

    // MARK: - Shared "today" stat block

    private func todayStat(
        value: String,
        unit: String,
        progress: Double,
        icon: String,
        isCompleted: Bool,
        waived: Bool
    ) -> some View {
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

// MARK: - Gym Countdown Button

// Pulled out of ActivityCard's gymActionButton if/else chain on purpose:
// TimelineView is a heavily generic type, and mixing it directly into a
// multi-branch @ViewBuilder if/else caused a "Generic parameter 'Content'
// could not be inferred" error. Isolating it in its own view, and further
// isolating the button-building work into a plain method with a small
// number of let bindings, keeps each piece simple enough for the type
// checker to resolve.
private struct GymCountdownButton: View {
    @ObservedObject var gymTracker: GymTracker
    let checkInDate: Date

    var body: some View {
        TimelineView(.periodic(from: checkInDate, by: 1)) { context in
            countdownButton(at: context.date)
        }
    }

    private func countdownButton(at now: Date) -> some View {
        let elapsed = now.timeIntervalSince(checkInDate)
        let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds
        let readyToCheckOut = canCheckOut && gymTracker.isInsideGeofence
        let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)
        let label = canCheckOut ? "Check Out" : timeString(from: remaining)
        let icon = canCheckOut ? "figure.walk.departure" : "timer"

        return Button {
            gymTracker.checkOut()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(readyToCheckOut ? Palette.background : Palette.textSecondary)
        .background(Capsule().fill(readyToCheckOut ? Palette.open : Palette.surfaceStroke))
        .disabled(!readyToCheckOut)
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview("iPhone") {
    ContentView()
}
