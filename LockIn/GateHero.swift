import SwiftUI

// MARK: - Gate Hero (Device Status Card)

struct GateHero: View {
    let isOpen: Bool?
    let deviceOnline: Bool
    let errorMessage: String?
    let goalsFullyMet: Bool?
    let availableToClaimMinutes: Int?
    let remainingMinutes: Int?
    let isClaiming: Bool
    let onClaim: () async -> Void

    private let lowBalanceThresholdMinutes = 10

    /// True only while genuinely open and running down a claimed balance
    /// that's getting close to zero — the state the amber warning exists
    /// to catch before it becomes a hard cutoff.
    private var isLowBalance: Bool {
        guard isOpen == true, goalsFullyMet != true, let remaining = remainingMinutes else { return false }
        return remaining > 0 && remaining <= lowBalanceThresholdMinutes
    }

    private var tint: Color {
        switch isOpen {
        case .some(true): isLowBalance ? Palette.waived : Palette.open
        case .some(false): Palette.locked
        case .none: Palette.neutral
        }
    }

    private var label: String {
        switch isOpen {
        case .some(true):
            if goalsFullyMet == true {
                return "UNLOCKED FOR TODAY"
            }
            if let remaining = remainingMinutes {
                return "OPEN — \(formatMinutes(remaining)) LEFT"
            }
            return "OPEN — SPENDING BALANCE"

        case .some(false):
            if !TimeUtils.isFreeTime() {
                return TimeUtils.lockoutLabel()
            }
            if let available = availableToClaimMinutes, available > 0 {
                return "TAP CLAIM TO UNLOCK"
            }
            return "LOCKED — GOALS NOT MET"

        case .none:
            return "SYNCING…"
        }
    }

    private var icon: String {
        switch isOpen {
        case .some(true): "lock.open.fill"
        case .some(false): "lock.fill"
        case .none: "questionmark"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityRow

            if TimeUtils.isFreeTime() {
                Divider().overlay(Palette.surfaceStroke)
                creditRow
            }

            if let errorMessage {
                errorRow(errorMessage)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: Identity row (icon + status label + online pill)

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.easeInOut(duration: 0.3), value: isOpen)

            VStack(alignment: .leading, spacing: 3) {
                Text("GATE STATUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textSecondary)
                Text(label)
                    .font(Typography.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            onlinePill
        }
    }

    private var onlinePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(deviceOnline ? Palette.open : Palette.locked)
                .frame(width: 6, height: 6)
            Text(deviceOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.background.opacity(0.6)))
        .overlay(Capsule().stroke(Palette.surfaceStroke, lineWidth: 1))
    }

    // MARK: - Credit row

    private var creditIcon: String {
        if goalsFullyMet == true {
            return "checkmark.circle.fill"
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return "gift.fill"
        }

        if (remainingMinutes ?? 0) > 0 {
            return "clock.fill"
        }

        return "gift"
    }

    private var creditTint: Color {
        if goalsFullyMet == true {
            return Palette.open
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return Palette.open
        }

        if let remaining = remainingMinutes {
            if remaining <= 0 {
                return Palette.locked
            }
            if remaining <= lowBalanceThresholdMinutes {
                return Palette.waived
            }
            return Palette.textSecondary
        }

        return Palette.textSecondary
    }

    private var showsClaimButton: Bool {
        goalsFullyMet != true && (availableToClaimMinutes ?? 0) > 0
    }

    private var creditRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: creditIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(creditTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                if goalsFullyMet == true {
                    Text("Goals complete — unlocked")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    // Credit that has been earned but not yet claimed.
                    if let available = availableToClaimMinutes, available > 0 {
                        HStack(spacing: 5) {
                            Text(isClaiming
                                ? "Claiming \(formatMinutes(available))…"
                                : "+\(formatMinutes(available)) available")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    // Credit already claimed and currently available to spend.
                    if let remaining = remainingMinutes, remaining > 0 {
                        Text("\(formatMinutes(remaining)) balance left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    } else if availableToClaimMinutes == nil || availableToClaimMinutes == 0 {
                        Text("No credit available")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if showsClaimButton {
                claimButton
            }
        }
    }

    private var claimButton: some View {
        Button {
            Task { await onClaim() }
        } label: {
            HStack(spacing: 5) {
                if isClaiming {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                } else {
                    Text("Claim")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Palette.open)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Palette.open.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Palette.open.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isClaiming)
    }

    // MARK: Error row

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(message)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.waived)
    }
}
