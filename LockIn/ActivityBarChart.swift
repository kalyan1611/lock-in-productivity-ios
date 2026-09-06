import SwiftUI

struct ActivityBarChart: View {
    let entries: [(date: Date, value: Double)]
    let target: Double
    let period: StatsPeriod

    private var maxValue: Double {
        max(entries.map(\.value).max() ?? 0, target)
    }

    private func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = period == .month ? "d" : "EEE"
        return formatter.string(from: date)
    }

    /// Month view has ~30 bars — only label every few to avoid crowding.
    private func shouldLabel(_ index: Int) -> Bool {
        period != .month || index % 5 == 0
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: period == .month ? 2 : 8) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let met = entry.value >= target
                    let heightFraction = maxValue > 0 ? entry.value / maxValue : 0
                    let barAreaHeight = geo.size.height - 16 // reserve for label

                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: period == .month ? 2 : 4)
                            .fill(met ? Palette.open : Palette.started)
                            .frame(height: max(3, barAreaHeight * heightFraction))
                        Text(shouldLabel(index) ? label(for: entry.date) : "")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}