import SwiftUI

// MARK: - Gate Hero (Device Status Card)

struct GateHero: View {
    let isOpen: Bool?
    let deviceOnline: Bool
    let errorMessage: String?
    let goalsFullyMet: Bool?
    let availableToClaimMinutes: Int?
    let remainingMinutes: Int?
    /// Whether the two goals required for `goalsFullyMet` were met via a
    /// waive-off rather than actually completed — used to avoid claiming
    /// "goals complete" when nothing was actually finished.
    let stepsWaivedToday: Bool
    let gymWaivedToday: Bool
    let leetcodeWaivedToday: Bool
    let isClaiming: Bool
    let onClaim: (Int) async -> Void

    private let lowBalanceThresholdMinutes = 10
    private let claimStepMinutes = 10

    @State private var isPickingAmount = false
    @State private var selectedMinutes: Double = 10

    // MARK: - State

    private var isLowBalance: Bool {
        guard isOpen == true,
              goalsFullyMet != true,
              let remaining = remainingMinutes
        else {
            return false
        }

        return remaining > 0 && remaining <= lowBalanceThresholdMinutes
    }

    private var unlockedViaWaiveOff: Bool {
        goalsFullyMet == true && (stepsWaivedToday && leetcodeWaivedToday && gymWaivedToday)
    }

    private var tint: Color {
        switch isOpen {
        case .some(true):
            isLowBalance ? Palette.waived : Palette.open
        case .some(false):
            Palette.locked
        case .none:
            Palette.neutral
        }
    }

    private var label: String {
        switch isOpen {
        case .some(true):
            if goalsFullyMet == true {
                return unlockedViaWaiveOff ? "UNLOCKED (WAIVED)" : "UNLOCKED FOR TODAY"
            }

            if let remaining = remainingMinutes {
                return "\(formatMinutes(remaining)) LEFT"
            }

            return "OPEN — SPENDING BALANCE"

        case .some(false):
            if !TimeUtils.isFreeTime() {
                return TimeUtils.lockoutLabel()
            }

            if let available = availableToClaimMinutes, available > 0 {
                return "TAP CLAIM TO UNLOCK"
            }

            return "GOALS NOT MET"

        case .none:
            return "SYNCING…"
        }
    }

    private var icon: String {
        switch isOpen {
        case .some(true):
            "lock.open.fill"
        case .some(false):
            "lock.fill"
        case .none:
            "questionmark"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityRow

            if TimeUtils.isFreeTime() {
                Divider()
                    .overlay(Palette.surfaceStroke)

                creditSection

                if isPickingAmount {
                    claimAmountPicker
                }
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
        .onChange(of: showsClaimButton) { _, nowShows in
            if !nowShows { isPickingAmount = false }
        }
    }

    // MARK: - Identity Row

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
                    .font(
                        .system(
                            size: 9,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
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

    // MARK: - Online Pill

    private var onlinePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(
                    deviceOnline
                        ? Palette.open
                        : Palette.locked
                )
                .frame(width: 6, height: 6)

            Text(deviceOnline ? "ONLINE" : "OFFLINE")
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .tracking(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Palette.background.opacity(0.6))
        )
        .overlay(
            Capsule()
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Compact Credit Section

    private var creditSection: some View {
        HStack(spacing: 0) {
            // Available credit
            HStack(spacing: 7) {
                Image(systemName: availableCreditIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(availableCreditTint)

                Text(availableCreditText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(availableCreditTextTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 10)

            // Divider
            Rectangle()
                .fill(Palette.surfaceStroke)
                .frame(width: 1, height: 22)

            Spacer(minLength: 10)

            // Current balance
            HStack(spacing: 7) {
                Image(systemName: balanceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(balanceTint)

                Text(balanceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(balanceTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Claim button
            if showsClaimButton {
                Spacer(minLength: 10)
                claimButton
            }
        }
        .frame(minHeight: 32)
    }

    // MARK: - Available Credit

    private var availableCreditIcon: String {
        if goalsFullyMet == true {
            return unlockedViaWaiveOff ? "ticket.fill" : "checkmark.circle.fill"
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return "gift.fill"
        }

        return "gift"
    }

    private var availableCreditTint: Color {
        if goalsFullyMet == true {
            return unlockedViaWaiveOff ? Palette.waived : Palette.open
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return Palette.open
        }

        return Palette.textSecondary
    }

    private var availableCreditText: String {
        if goalsFullyMet == true {
            return unlockedViaWaiveOff ? "Unlocked via waive-off" : "Goals complete"
        }

        if let available = availableToClaimMinutes,
           available > 0
        {
            return "+\(formatMinutes(available)) available"
        }

        return "No credit"
    }

    // MARK: - Balance

    private var balanceIcon: String {
        if let remaining = remainingMinutes,
           remaining > 0
        {
            return "clock.fill"
        }

        return "clock"
    }

    private var balanceTint: Color {
        guard let remaining = remainingMinutes,
              remaining > 0
        else {
            return Palette.textSecondary
        }

        if remaining <= lowBalanceThresholdMinutes {
            return Palette.waived
        }

        return Palette.textPrimary
    }

    private var availableCreditTextTint: Color {
        if goalsFullyMet == true {
            return unlockedViaWaiveOff ? Palette.waived : Palette.open
        }

        if (availableToClaimMinutes ?? 0) > 0 {
            return Palette.textPrimary
        }

        return Palette.textSecondary
    }

    private var balanceText: String {
        if goalsFullyMet == true {
            return "Unlocked"
        }

        if let remaining = remainingMinutes,
           remaining > 0
        {
            return "\(formatMinutes(remaining)) balance"
        }

        return "No balance"
    }

    // MARK: - Claim Button & Amount Picker

    /// Available minutes rounded down to a whole claim step — the slider
    /// only ever offers multiples of `claimStepMinutes`, matching what the
    /// ESP32 will actually honor.
    private var availableSteppedMinutes: Int {
        guard let available = availableToClaimMinutes else { return 0 }
        return (available / claimStepMinutes) * claimStepMinutes
    }

    private var showsClaimButton: Bool {
        goalsFullyMet != true && availableSteppedMinutes >= claimStepMinutes
    }

    private var claimButton: some View {
        Button {
            selectedMinutes = Double(availableSteppedMinutes) // default to everything available
            isPickingAmount = true
        } label: {
            Text("Claim")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.open)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Palette.open.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            Palette.open.opacity(0.4),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Small slider (10m -> everything available, in 10m steps) that
    /// appears once "Claim" is tapped, so you choose exactly how much of
    /// today's earned credit to spend rather than always claiming it all.
    private var claimAmountPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claim \(formatMinutes(Int(selectedMinutes)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)

                Spacer()

                Button {
                    isPickingAmount = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    let minutes = Int(selectedMinutes)
                    isPickingAmount = false
                    Task { await onClaim(minutes) }
                } label: {
                    if isClaiming {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.open)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isClaiming)
            }

            Slider(
                value: $selectedMinutes,
                in: Double(claimStepMinutes) ... Double(max(availableSteppedMinutes, claimStepMinutes)),
                step: Double(claimStepMinutes)
            )
            .tint(Palette.open)
        }
        .padding(.top, 2)
    }

    // MARK: Error Row

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

#Preview("iPhone") {
    ContentView()
}
