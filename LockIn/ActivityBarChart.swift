import SwiftUI

// MARK: - Activity Bar Chart

/// Generic week/month bar chart used by Steps, Gym, and LeetCode.
/// Week view (7 bars, room to spare) always shows each bar's total above
/// it. Month view (~30 bars, tight) shows nothing above the bars at all —
/// a label above a ~7pt-wide bar is unreadable no matter the font size —
/// and instead just reports which bar is selected via `selectedIndex`, so
/// the caller can render a proper, readable detail row elsewhere (e.g.
/// under the Week/Month switcher).
///
/// Each bar column is laid out as three FIXED-height rows (top label,
/// bar area, day label) rather than relying on a `Spacer` to bottom-align
/// content — this makes every column's vertical geometry deterministic and
/// identical, which matters because the optional target line (see
/// `showTargetLine`) is positioned using those exact same constants. If the
/// bar area's real height ever drifted from what the line's offset assumes,
/// the two would silently disagree; fixed rows make that impossible.
struct ActivityBarChart: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    struct Entry {
        let date: Date
        let segments: [Segment]

        var total: Double {
            segments.reduce(0) { $0 + $1.value }
        }
    }

    let entries: [Entry]
    let target: Double
    let period: StatsPeriod
    /// Selected bar index, owned by the caller so it can render a detail
    /// view for the selection outside this chart. Only meaningful in month
    /// view — week bars aren't tappable (see the tap gesture below).
    @Binding var selectedIndex: Int?
    /// Formats a raw value into display text, e.g. "6,743" or "45m".
    /// Used for the per-bar total shown above each bar in week view.
    let valueLabel: (Double) -> String
    /// Whether to draw a dashed target-goal line. Steps and Gym use a
    /// single green/blue bar color to show met-vs-short, so the line is
    /// redundant there; LeetCode's bars are stacked easy/medium/hard
    /// segments with no single met/short color, so the line is the only
    /// way to see "did today clear target" at a glance. Defaults to true.
    var showTargetLine: Bool = true

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

    private var cornerRadius: CGFloat {
        period == .month ? 2 : 4
    }

    private var topLabelFontSize: CGFloat {
        11
    }

    /// Small fixed inset so bars don't touch the very edge of the chart's
    /// bounding box.
    private let axisChartGap: CGFloat = 4

    /// Fixed height of each bar's own day-label row (e.g. "Tue", "14").
    private let axisLabelHeight: CGFloat = 12

    /// Vertical gap between the three fixed rows in each bar column
    /// (top label / bar area / day label).
    private let rowSpacing: CGFloat = 3

    /// Reserved height above the bar for week view's per-bar total label.
    /// Month reserves almost nothing since no per-bar label renders there
    /// anymore — that space goes to taller bars instead.
    private var reservedTopHeight: CGFloat {
        period == .month ? 4 : 16
    }

    /// Fraction of the way down from the top of the bar area the target
    /// line should sit — 0 at the very top (target == scale max), 1 at the
    /// baseline. `nil` when there's nothing to draw.
    private var targetLineFraction: CGFloat? {
        guard showTargetLine, target > 0, maxValue > 0 else { return nil }
        let clamped = min(target / maxValue, 1)
        return CGFloat(1 - clamped)
    }

    var body: some View {
        GeometryReader { geo in
            let barSpacing: CGFloat = period == .month ? 2 : 8
            // Same three constants that size each bar column below —
            // reused here so the target line's offset can never drift
            // from what the bars themselves use.
            let verticalOverhead = axisLabelHeight + reservedTopHeight + rowSpacing * 2
            let chartWidth = max(geo.size.width - axisChartGap, 20)
            let barWidth = (chartWidth - barSpacing * CGFloat(max(entries.count - 1, 0))) / CGFloat(max(entries.count, 1))
            let barAreaHeight = max(geo.size.height - verticalOverhead, 20)

            ZStack(alignment: .topLeading) {
                barsRow(barWidth: barWidth, barSpacing: barSpacing, barAreaHeight: barAreaHeight)
                    .frame(width: chartWidth, height: geo.size.height, alignment: .top)

                if let fraction = targetLineFraction {
                    TargetLine()
                        .frame(width: chartWidth, height: 1)
                        // Top of the bar-area row is exactly reservedTopHeight
                        // + rowSpacing down from the top of the chart, since
                        // every row above it now has a fixed, known height —
                        // no Spacer-driven guesswork about where that lands.
                        .offset(y: reservedTopHeight + rowSpacing + fraction * barAreaHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .padding(.leading, axisChartGap)
        }
    }

    // MARK: - Bars

    private func barsRow(barWidth: CGFloat, barSpacing: CGFloat, barAreaHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: barSpacing) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isSelected = selectedIndex == index

                VStack(spacing: rowSpacing) {
                    topRow(for: entry)

                    ZStack(alignment: .bottom) {
                        stackedBar(entry: entry, isSelected: isSelected, maxHeight: barAreaHeight)
                    }
                    .frame(height: barAreaHeight, alignment: .bottom)

                    Text(shouldShowAxisLabel(index) ? dayLabel(entry.date) : "")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(height: axisLabelHeight, alignment: .top)
                }
                .frame(width: barWidth)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Week already shows every bar's value up top, so
                    // there's nothing a tap would reveal — only month
                    // (which relies on the external detail row) needs this.
                    guard period == .month else { return }
                    selectedIndex = isSelected ? nil : index
                }
            }
        }
    }

    // MARK: - Top row (week only — total above each bar; fixed height always)

    private func topRow(for entry: Entry) -> some View {
        Group {
            if period != .month, entry.total > 0 {
                Text(valueLabel(entry.total))
                    .font(.system(size: topLabelFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
                    .lineLimit(1)
            } else {
                Color.clear
            }
        }
        .frame(height: reservedTopHeight, alignment: .bottom)
    }

    // MARK: - Bar (single color, stacked segments, or empty-day placeholder)

    @ViewBuilder
    private func stackedBar(entry: Entry, isSelected: Bool, maxHeight: CGFloat) -> some View {
        let met = entry.total >= target
        let isStacked = entry.segments.count > 1

        Group {
            if entry.total <= 0 {
                // Zero-value day — a minimum-height placeholder bar so the
                // day still reads as present, rather than vanishing.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Palette.surfaceStroke)
                    .frame(height: 3)
            } else {
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
            }
        }
        .opacity(isSelected || selectedIndex == nil ? 1 : 0.4)
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Palette.textPrimary, lineWidth: 1.5)
                : nil
        )
    }
}

// MARK: - Target Line

/// A single dashed horizontal reference line spanning whatever width it's
/// given. GeometryReader is used just to read that width, since Path needs
/// concrete points rather than a flexible frame.
private struct TargetLine: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(
                Palette.textSecondary.opacity(0.6),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
        .frame(height: 1)
    }
}
