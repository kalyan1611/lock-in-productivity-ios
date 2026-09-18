import SwiftUI

/// Legacy standalone card — superseded by ActivityCard's LeetCode tab and
/// not currently instantiated anywhere in ContentView. Left in the tree in
/// case it's still wanted for something; not deleted outright since that's
/// a product call, not a cleanup call.
struct LeetCodeCard: View {
    @ObservedObject var leetCode: LeetCodeManager
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void

    var body: some View {
        let isCompleted = leetCode.isGoalMet

        GoalCardShell(
            title: "Leetcode",
            icon: "chevron.left.forwardslash.chevron.right",
            progress: leetCode.progress,
            color: GoalColor.forProgress(leetCode.progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: waiveRemaining,
            onTapWaiveOff: onTapWaiveOff
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if leetCode.isLoading {
                    ProgressView()
                        .tint(Palette.textSecondary)
                } else {
                    Text("\(leetCode.totalTodayCount)")
                        .font(Typography.display(28))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                Text("of \(leetCode.targetProblems) problems")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        } footer: {
            difficultyBreakdown
                .padding(.top, 4)
        }
    }

    private var difficultyBreakdown: some View {
        HStack(spacing: 0) {
            difficultyColumn(label: "EASY", count: leetCode.easyTodayCount, color: Palette.open)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "MEDIUM", count: leetCode.mediumTodayCount, color: Palette.waived)
            Divider().overlay(Palette.surfaceStroke).frame(height: 20)
            difficultyColumn(label: "HARD", count: leetCode.hardTodayCount, color: Palette.locked)
        }
    }

    private func difficultyColumn(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
