import SwiftUI

/// Legacy standalone card — superseded by ActivityCard's Steps tab and not
/// currently instantiated anywhere in ContentView. Left in the tree in case
/// it's still wanted for something; not deleted outright since that's a
/// product call, not a cleanup call.
struct StepsCard: View {
    @ObservedObject var healthKit: HealthKitManager
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void

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
            }
        } footer: {
            EmptyView()
        }
    }
}
