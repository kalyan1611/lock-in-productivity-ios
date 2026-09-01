import SwiftUI

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
}
