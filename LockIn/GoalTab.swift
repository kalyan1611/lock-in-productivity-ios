import SwiftUI

enum GoalTab: String, CaseIterable {
    case steps = "Steps"
    case gym = "Gym"
    case leetcode = "LeetCode"

    var icon: String {
        switch self {
        case .steps: "figure.walk"
        case .gym: "dumbbell.fill"
        case .leetcode: "chevron.left.forwardslash.chevron.right"
        }
    }

    var waiveOffType: NetworkManager.WaiveOffType {
        switch self {
        case .steps: .steps
        case .gym: .gym
        case .leetcode: .leetcode
        }
    }
}

/// Today's stat is always visible in ActivityCard now — this only controls
/// the history chart underneath it, so there's no "Day" case anymore.
enum StatsPeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

struct GoalTabSwitcher: View {
    @Binding var selection: GoalTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GoalTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Palette.background : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(selection == tab ? Palette.textPrimary : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.surfaceRaised))
        .overlay(Capsule().stroke(Palette.surfaceStroke, lineWidth: 1))
    }
}

struct PeriodSwitcher: View {
    @Binding var selection: StatsPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                Button {
                    selection = period
                } label: {
                    Text(period.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(selection == period ? Palette.background : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selection == period ? Palette.textPrimary : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
