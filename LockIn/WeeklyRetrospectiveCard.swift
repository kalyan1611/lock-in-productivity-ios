import SwiftUI

// MARK: - Weekly Retrospective Card

/// Summarizes the most recently *completed* calendar week (Monday-Sunday)
/// using `DailyOutcomeStore`. Deliberately never shows the current,
/// in-progress week — comparing a partial week against a full one is
/// misleading, and today's live state is already visible everywhere else
/// in the app (see `ActivityCard`). This card only answers "how did last
/// week go," and only once there's a real answer to give.
///
/// No streaks, no fire emojis, no comparison to other weeks beyond the
/// plain numbers — this is meant to read as a quiet, honest status check,
/// not a gamified nudge.
///
/// Not currently instantiated anywhere in ContentView — ActivityCard's own
/// inline "LAST WK / LAST MO" row (see `periodSwitcherRow`) now covers the
/// same aggregate summary from `DailyOutcomeStore.lastWeekSummary`. This
/// card still does something that one doesn't: a full day-by-day dot grid
/// per goal. Left in the tree pending a decision on whether to wire it in
/// alongside the inline summary or retire it — not deleted outright since
/// that's a product call, not a cleanup call.
struct WeeklyRetrospectiveCard: View {
    private struct DayOutcomes {
        let date: Date
        let steps: GoalOutcome?
        let gym: GoalOutcome?
        let leetcode: GoalOutcome?

        var allMet: Bool {
            steps == .met && gym == .met && leetcode == .met
        }

        var hasAnyData: Bool {
            steps != nil || gym != nil || leetcode != nil
        }
    }

    // MARK: - Week Computation

    /// The seven days of the most recently completed Mon-Sun week, oldest
    /// first. Mirrors DailyOutcomeStore.lastWeekSummary's week boundary
    /// exactly (tm_wday 0 = Sun ... 6 = Sat, daysSinceMonday = wday == 0 ?
    /// 6 : wday - 1 — Calendar's `weekday` is tm_wday + 1, so the same rule
    /// becomes `weekday - 2`, with Sunday special-cased to 6) so both stay
    /// on the same week grid.
    private var lastWeekDays: [DayOutcomes] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2

        guard let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today),
              let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)
        else {
            return []
        }

        return (0 ..< 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: lastMonday) else { return nil }
            return DayOutcomes(
                date: date,
                steps: DailyOutcomeStore.outcome(goal: .steps, date: date),
                gym: DailyOutcomeStore.outcome(goal: .gym, date: date),
                leetcode: DailyOutcomeStore.outcome(goal: .leetcode, date: date)
            )
        }
    }

    /// False until at least one day in the window has a real recorded
    /// outcome — i.e. the logging shipped before last week ended. Drives
    /// the empty-state fallback below.
    private var hasData: Bool {
        lastWeekDays.contains(where: \.hasAnyData)
    }

    private var fullyMetCount: Int {
        lastWeekDays.filter(\.allMet).count
    }

    private var waivedCount: Int {
        lastWeekDays.reduce(0) { total, day in
            total + [day.steps, day.gym, day.leetcode].filter { $0 == .waived }.count
        }
    }

    private var dateRangeLabel: String {
        guard let first = lastWeekDays.first?.date, let last = lastWeekDays.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if hasData {
                summaryRow
                weekdayLabelsRow
                goalRows
            } else {
                emptyState
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("LAST WEEK")
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if hasData {
                Text(dateRangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(fullyMetCount)")
                .font(Typography.display(30))
                .foregroundStyle(fullyMetCount == 7 ? Palette.open : Palette.textPrimary)

            Text("/ 7 days fully met")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if waivedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(waivedCount) of \(AppConfig.WaiveOff.weeklyTotal) waived")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.waived)
            }
        }
    }

    // MARK: - Weekday Labels (aligned above the dot rows)

    private var weekdayLabelsRow: some View {
        HStack(spacing: 10) {
            // Matches goalRow's icon column width so the labels line up
            // exactly above their corresponding dot columns.
            Color.clear.frame(width: 16)

            HStack(spacing: 6) {
                ForEach(lastWeekDays, id: \.date) { day in
                    Text(weekdayInitial(day.date))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 10)
                }
            }
        }
    }

    private func weekdayInitial(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE" // single-letter weekday (M, T, W...)
        return formatter.string(from: date)
    }

    // MARK: - Per-Goal Dot Rows

    private var goalRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            goalRow(icon: "figure.walk", outcomes: lastWeekDays.map(\.steps))
            goalRow(icon: "dumbbell.fill", outcomes: lastWeekDays.map(\.gym))
            goalRow(icon: "chevron.left.forwardslash.chevron.right", outcomes: lastWeekDays.map(\.leetcode))
        }
    }

    private func goalRow(icon: String, outcomes: [GoalOutcome?]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 16)

            HStack(spacing: 6) {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                    Circle()
                        .fill(dotColor(for: outcome))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private func dotColor(for outcome: GoalOutcome?) -> Color {
        switch outcome {
        case .met: Palette.open
        case .waived: Palette.waived
        case .missed: Palette.locked
        case .none: Palette.neutral
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("Still collecting data — check back once a full week has passed.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("iPhone") {
    ContentView()
}
