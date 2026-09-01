import SwiftUI

struct GymCard: View {
    @ObservedObject var gymTracker: GymTracker
    let waived: Bool
    let waiveRemaining: Int?
    let onTapWaiveOff: () -> Void

    private let checkButtonsHeight: CGFloat = 46

    var body: some View {
        let isCompleted = gymTracker.isGymSessionCompleted
        let progress = gymTracker.targetGymDurationSeconds > 0
            ? gymTracker.totalSecondsToday / gymTracker.targetGymDurationSeconds : 0

        GoalCardShell(
            title: "Workout",
            icon: "dumbbell.fill",
            progress: progress,
            color: GoalColor.forProgress(progress, isCompleted: isCompleted, waived: waived),
            isCompleted: isCompleted,
            waived: waived,
            waiveRemaining: waiveRemaining,
            onTapWaiveOff: onTapWaiveOff
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(gymTracker.totalSecondsToday) / 60) min")
                    .font(Typography.display(22))
                    .foregroundStyle(Palette.textPrimary)
                Text("of \(gymTracker.targetGymDurationMinutes) min target")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                if !isCompleted {
                    Text("Full session: +45m")
                        .font(.caption2)
                        .foregroundStyle(Palette.neutral)
                }
            }
        } footer: {
            gymActionButton
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var gymActionButton: some View {
        if gymTracker.isCheckedIn, let checkInDate = gymTracker.checkInDate {
            TimelineView(.periodic(from: checkInDate, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(checkInDate)
                let remaining = max(gymTracker.targetGymDurationSeconds - elapsed, 0)
                let canCheckOut = elapsed >= gymTracker.targetGymDurationSeconds
                let readyToCheckOut = canCheckOut && gymTracker.isInsideGeofence

                VStack(spacing: 10) {
                    Button {
                        gymTracker.checkOut()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: canCheckOut ? "figure.walk.departure" : "timer")
                            Text(canCheckOut ? "Check Out" : timeString(from: remaining))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: checkButtonsHeight)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(readyToCheckOut ? Palette.background : Palette.textSecondary)
                    .background(Capsule().fill(readyToCheckOut ? Palette.open : Palette.surfaceStroke))
                    .disabled(!readyToCheckOut)

                    gymGuidanceLabel
                }
            }
        } else if gymTracker.hasCheckedOutToday {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Session complete")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.open)
                .frame(maxWidth: .infinity)
                .frame(height: checkButtonsHeight)
                .background(Capsule().fill(Palette.open.opacity(0.12)))

                Text(workoutDurationText)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        } else {
            VStack(spacing: 10) {
                Button {
                    gymTracker.checkIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text("Check In")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: checkButtonsHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(gymTracker.isInsideGeofence ? Palette.background : Palette.textSecondary)
                .background(Capsule().fill(gymTracker.isInsideGeofence ? Palette.open : Palette.surfaceStroke))
                .disabled(!gymTracker.isInsideGeofence)

                gymGuidanceLabel
            }
        }
    }

    private var gymGuidanceLabel: some View {
        Group {
            if gymTracker.isInsideGeofence {
                gymGuidanceRow(icon: "location.fill", text: "Inside gym zone", tint: Palette.open)
            } else if gymTracker.distanceToGym != nil {
                gymGuidanceRow(icon: "location", text: formattedDistance, tint: Palette.textSecondary)
            } else {
                gymGuidanceRow(icon: "location.slash", text: "Location unknown", tint: Palette.textSecondary)
            }
        }
        .font(.caption2)
    }

    private func gymGuidanceRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundStyle(tint)
    }

    private var formattedDistance: String {
        guard let distance = gymTracker.distanceToGym else { return "" }
        return distance >= 1000
            ? String(format: "%.1f km away", distance / 1000)
            : String(format: "%.0f m away", distance)
    }

    private var workoutDurationText: String {
        guard let inTime = gymTracker.lastCheckInDate, let outTime = gymTracker.lastCheckOutDate else {
            return "Workout logged for today"
        }
        let minutes = Int(outTime.timeIntervalSince(inTime) / 60)
        return "Workout duration: \(minutes) mins"
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
