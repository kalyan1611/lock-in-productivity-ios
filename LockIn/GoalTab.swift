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
    /// Fires with (oldTab, newTab) whenever a tap actually changes the
    /// selection. Callers that want a direction-aware content transition
    /// (see ActivityCard) should set their direction state from inside
    /// this closure — it's invoked from inside the same `withAnimation`
    /// block as the `selection` write itself, so both land in one
    /// transaction and the content transition sees the right direction on
    /// its very first render instead of one frame late.
    var onSelect: ((GoalTab, GoalTab) -> Void)? = nil

    /// Shared id for the highlight capsule. Because only the currently
    /// selected button inserts a capsule carrying this id, SwiftUI treats
    /// it as the same view moving between buttons rather than one fading
    /// out while another fades in — that's what makes the highlight slide
    /// instead of crossfade.
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GoalTab.allCases, id: \.self) { tab in
                Button {
                    guard tab != selection else { return }
                    let old = selection
                    withAnimation(.easeInOut(duration: 0.25)) {
                        onSelect?(old, tab)
                        selection = tab
                    }
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
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Palette.textPrimary)
                                .matchedGeometryEffect(id: "goalTabPill", in: pillNamespace)
                        }
                    }
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

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = period
                    }
                } label: {
                    Text(period.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(selection == period ? Palette.background : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selection == period {
                                Capsule()
                                    .fill(Palette.textPrimary)
                                    .matchedGeometryEffect(id: "periodPill", in: pillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
