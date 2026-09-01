import SwiftUI

struct StepsCard: View {
    @ObservedObject var healthKit: HealthKitManager
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void

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

    var body: some View {
        let isCompleted = healthKit.areTodaysStepsCompleted
        let progress = healthKit.targetSteps > 0
            ? Double(healthKit.todaySteps) / Double(healthKit.targetSteps) : 0

        GoalCardShell(
            title: "Steps",
            icon: "figure.walk",
            progress: progress,
            color: GoalColor.forProgress(progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: waiveRemaining,
            onTapWaiveOff: onTapWaiveOff
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
}
