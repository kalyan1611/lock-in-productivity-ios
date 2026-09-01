import SwiftUI

// MARK: - Ring Progress

struct RingProgress: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.surfaceStroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0015, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
    }
}

// MARK: - Goal Card Shell

// Common frame every goal card (Steps / Gym / LeetCode) is built on: a
// title row with an optional waive-off ticket, a progress ring + icon,
// caller-supplied content, and a caller-supplied footer.

struct GoalCardShell<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let progress: Double
    let color: Color
    let isCompleted: Bool
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 16) {
                ZStack {
                    RingProgress(progress: progress, color: color, lineWidth: 7)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                content
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(title.uppercased())
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            if !isCompleted, !waived, TimeUtils.isFreeTime(), let waiveRemaining {
                TicketBadge(remaining: waiveRemaining, action: onTapWaiveOff)
            }
        }
    }
}

// MARK: - Ticket Badge

// Same recipe as GateHero's `onlinePill` and `claimButton` — translucent
// dark fill + a 1pt stroke in the semantic color, rather than a solid
// filled chip. "ticket" reads as "redeem for a skip" more directly than
// a plain X or calendar icon would.

struct TicketBadge: View {
    let remaining: Int
    let action: () -> Void

    private var tint: Color {
        remaining > 0 ? Palette.waived : Palette.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.background.opacity(0.5)))
            .overlay(Capsule().stroke(remaining > 0 ? tint.opacity(0.4) : Palette.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(remaining <= 0)
    }
}
