import SwiftUI
import UIKit

// MARK: - Share Card Data

/// One structured breakdown row — an exercise (gym) or a difficulty count
/// (LeetCode). `color` only matters for LeetCode's dot; gym rows ignore it.
struct ShareBreakdownItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var color: Color = Palette.textSecondary
}

/// Just what was actually done, not the target — no goal, no progress bar.
struct ShareStatData: Identifiable {
    let tab: GoalTab
    var id: GoalTab {
        tab
    }

    let label: String // "STEPS" / "WORKOUT" / "LEETCODE"
    let value: String // "12,450 steps" / "38 min" / "7 solved"
    /// Small pill next to `label` — the split name for gym ("PULL").
    /// Nil for Steps/LeetCode.
    var badge: String?
    /// Gym: one row per logged exercise (name left, sets×reps right).
    /// LeetCode: one colored dot+count per difficulty actually solved.
    /// Empty for Steps.
    var breakdown: [ShareBreakdownItem] = []
}

// MARK: - Shareable Card (rendered to an image)

/// One block per selected stat, stacked — no fixed height, so a one-stat
/// share is exactly one block tall and a three-stat share is exactly
/// three, never padded to fit some imagined maximum.
struct ShareableStatCard: View {
    let stats: [ShareStatData]
    let date: Date

    static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    statBlock(stat)
                    if index < stats.count - 1 {
                        Divider().overlay(Palette.surfaceStroke)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: Self.width, alignment: .topLeading)
        .background(Palette.background)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text(dateText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Stat block

    private func statBlock(_ stat: ShareStatData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow(stat)

            if stat.tab == .gym, !stat.breakdown.isEmpty {
                exerciseList(stat.breakdown)
            }

            if stat.tab == .leetcode, !stat.breakdown.isEmpty {
                difficultyBadges(stat.breakdown)
            }
        }
        .padding(.vertical, 12)
    }

    private func headerRow(_ stat: ShareStatData) -> some View {
        HStack(spacing: 10) {
            Image(systemName: stat.tab.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.open)
                .frame(width: 22)

            Text(stat.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.textSecondary)

            if let badge = stat.badge {
                Text(badge.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Palette.open)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.open.opacity(0.14)))
            }

            Spacer(minLength: 12)

            Text(stat.value)
                .font(Typography.display(20))
                .foregroundStyle(Palette.textPrimary)
        }
    }

    /// One aligned row per exercise — name left (truncates rather than
    /// wraps into a paragraph), sets×reps right in a fixed-width column
    /// so the numbers line up down the list.
    private func exerciseList(_ items: [ShareBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Palette.surfaceStroke)
                        .frame(width: 4, height: 4)
                    Text(item.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 10)
                    Text(item.value)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
        }
        .padding(.leading, 32)
    }

    /// Compact colored dot + count per difficulty, matching the app's own
    /// easy/medium/hard palette — no plain comma-joined text.
    private func difficultyBadges(_ items: [ShareBreakdownItem]) -> some View {
        HStack(spacing: 16) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Circle().fill(item.color).frame(width: 7, height: 7)
                    Text(item.value)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                    Text(item.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 32)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Share Card Picker (sheet)

/// Multi-select checklist — pick any combination of Steps/Gym/LeetCode to
/// include in one shared image, not just one at a time.
struct ShareCardPicker: View {
    let initialTab: GoalTab
    let dataProvider: (GoalTab) -> ShareStatData

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTabs: Set<GoalTab>
    @State private var renderedImage: UIImage?
    @State private var isShareSheetPresented = false

    init(initialTab: GoalTab, dataProvider: @escaping (GoalTab) -> ShareStatData) {
        self.initialTab = initialTab
        self.dataProvider = dataProvider
        _selectedTabs = State(initialValue: [initialTab])
    }

    /// GoalTab.allCases order (Steps → Gym → LeetCode), filtered to the
    /// selection — keeps row order stable regardless of tap order.
    private var orderedSelection: [GoalTab] {
        GoalTab.allCases.filter { selectedTabs.contains($0) }
    }

    private var currentStats: [ShareStatData] {
        orderedSelection.map(dataProvider)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    previewArea
                        .padding(.vertical, 12)
                }

                VStack(spacing: 16) {
                    selectionBar
                        .padding(.horizontal, 20)
                    shareButton
                }
                .padding(.top, 12)
                .background(Palette.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Share Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShareSheetPresented) {
            if let renderedImage {
                ShareSheet(activityItems: [renderedImage])
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if currentStats.isEmpty {
            Text("Select at least one to share")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else {
            ShareableStatCard(stats: currentStats, date: Date())
        }
    }

    private var shareButton: some View {
        Button {
            share()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.background)
        .background(Capsule().fill(currentStats.isEmpty ? Palette.surfaceStroke : Palette.open))
        .disabled(currentStats.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    /// Same capsule-bar look as GoalTabSwitcher on the main screen — icon
    /// + label pills in one row — but each pill toggles independently
    /// (no shared sliding highlight) since more than one can be selected
    /// at once here.
    private var selectionBar: some View {
        HStack(spacing: 4) {
            ForEach(GoalTab.allCases, id: \.self) { tab in
                selectionButton(tab)
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.surfaceRaised))
        .overlay(Capsule().stroke(Palette.surfaceStroke, lineWidth: 1))
    }

    private func selectionButton(_ tab: GoalTab) -> some View {
        let isSelected = selectedTabs.contains(tab)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedTabs.remove(tab)
                } else {
                    selectedTabs.insert(tab)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Palette.background : Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                if isSelected {
                    Capsule().fill(Palette.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func share() {
        guard !currentStats.isEmpty else { return }
        let card = ShareableStatCard(stats: currentStats, date: Date())
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return }
        renderedImage = image
        isShareSheetPresented = true
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
