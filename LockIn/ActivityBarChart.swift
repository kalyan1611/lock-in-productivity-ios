import SwiftUI

// MARK: - Activity Bar Chart

/// Generic week/month bar chart used by Steps, Gym, and LeetCode. Each bar
/// always shows its total value above it. Tapping a bar selects it (dims
/// the others); if that bar has more than one segment (LeetCode's
/// easy/medium/hard split), the top label switches from the total to the
/// per-segment composition, color-coded to match the segments.
struct ActivityBarChart: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    struct Entry {
        let date: Date
        let segments: [Segment]

        var total: Double { segments.reduce(0) { $0 + $1.value } }
    }

    let entries: [Entry]
    let target: Double
    let period: StatsPeriod
    /// Formats a raw value into display text, e.g. "6,743" or "45m".
    let valueLabel: (Double) -> String

    @State private var selectedIndex: Int?

    private var maxValue: Double {
        max(entries.map(\.total).max() ?? 0, target, 1)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = period == .month ? "d" : "EEE"
        return formatter.string(from: date)
    }

    /// Month view has ~30 bars — only label the x-axis every few to avoid crowding.
    private func shouldShowAxisLabel(_ index: Int) -> Bool {
        period != .month || index % 5 == 0
    }

    private var cornerRadius: CGFloat { period == .month ? 2 : 4 }

    var body: some View {
        GeometryReader { geo in
            let barSpacing: CGFloat = period == .month ? 2 : 8
            let barWidth = (geo.size.width - barSpacing * CGFloat(max(entries.count - 1, 0))) / CGFloat(max(entries.count, 1))
            let topLabelHeight: CGFloat = period == .month ? 20 : 14
            let axisLabelHeight: CGFloat = 12
            let barAreaHeight = max(geo.size.height - topLabelHeight - axisLabelHeight, 0)

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isSelected = selectedIndex == index
                    let showBreakdown = isSelected && entry.segments.count > 1

                    VStack(spacing: 3) {
                        topLabel(for: entry, showBreakdown: showBreakdown)
                            .frame(height: topLabelHeight)

                        stackedBar(entry: entry, isSelected: isSelected, maxHeight: barAreaHeight)

                        Text(shouldShowAxisLabel(index) ? dayLabel(entry.date) : "")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(width: barWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = isSelected ? nil : index
                    }
                }
            }
        }
    }

    // MARK: - Top label (total, or per-segment breakdown when selected)

    @ViewBuilder
    private func topLabel(for entry: Entry, showBreakdown: Bool) -> some View {
        if showBreakdown {
            HStack(spacing: 4) {
                ForEach(Array(entry.segments.enumerated()), id: \.offset) { _, segment in
                    if segment.value > 0 {
                        Text(valueLabel(segment.value))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(segment.color)
                    }
                }
            }
        } else if entry.total > 0 {
            Text(valueLabel(entry.total))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
        } else {
            Color.clear
        }
    }

    // MARK: - Bar (single color, or stacked segments)

    @ViewBuilder
    private func stackedBar(entry: Entry, isSelected: Bool, maxHeight: CGFloat) -> some View {
        let met = entry.total >= target
        let isStacked = entry.segments.count > 1

        VStack(spacing: isStacked ? 1 : 0) {
            // Reversed so the first segment (e.g. easy) ends up at the bottom of the bar.
            ForEach(Array(entry.segments.enumerated().reversed()), id: \.offset) { _, segment in
                let heightFraction = segment.value / maxValue
                Rectangle()
                    .fill(isStacked ? segment.color : (met ? Palette.open : Palette.started))
                    .frame(height: segment.value > 0 ? max(3, maxHeight * heightFraction) : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .opacity(isSelected || selectedIndex == nil ? 1 : 0.4)
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.textPrimary, lineWidth: 1.5)
                : nil
        )
    }
}
