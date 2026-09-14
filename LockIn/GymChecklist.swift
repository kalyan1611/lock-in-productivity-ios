import SwiftUI

// MARK: - Gym Checklist (shown while checked in)

/// Replaces the history chart section for the duration of a session — see
/// ActivityCard.gymContent. Reps default to the prescribed scheme (rarely
/// changes mid-workout); sets are logged live via "+1 set" as each one is
/// finished, starting at 0 — not assumed complete. Skip is a separate
/// explicit state, distinct from "0 sets logged so far."
struct GymChecklist: View {
    let split: WorkoutSplit
    @Binding var log: [ExerciseLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY · \(split.title.uppercased())")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)

            VStack(spacing: 8) {
                ForEach($log) { $exercise in
                    exerciseRow($exercise, prescribed: prescription(for: exercise.name))
                }
            }
        }
    }

    private func prescription(for name: String) -> ExercisePrescription? {
        split.exercises.first { $0.name == name }
    }

    private func exerciseRow(_ exercise: Binding<ExerciseLog>, prescribed: ExercisePrescription?) -> some View {
        let isSkipped = exercise.wrappedValue.skipped
        let targetSets = prescribed?.sets ?? exercise.wrappedValue.setsDone

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(exercise.wrappedValue.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSkipped ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(isSkipped)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                skipToggle(exercise)
            }

            if !isSkipped {
                HStack(spacing: 10) {
                    setsCounter(exercise, target: targetSets)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text("reps")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                        repsStepper(exercise)
                    }

                    HStack(spacing: 6) {
                        if let prescribed {
                            Text("target \(prescribed.reps)")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Text("reps")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                        repsStepper(exercise)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
        .opacity(isSkipped ? 0.55 : 1)
    }

    // MARK: - Sets (logged live: +1 set per completed set)

    private func setsCounter(_ exercise: Binding<ExerciseLog>, target: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                exercise.wrappedValue.setsDone = max(0, exercise.wrappedValue.setsDone - 1)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
            }

            Text("\(exercise.wrappedValue.setsDone)/\(target) sets")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(exercise.wrappedValue.setsDone >= target && target > 0 ? Palette.open : Palette.textPrimary)
                .frame(minWidth: 64, alignment: .leading)

            Button {
                exercise.wrappedValue.setsDone += 1
                exercise.wrappedValue.reps = 0 // reps counts the *next* set, not the one just logged
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                    Text("Set")
                }
                .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Palette.open)
        }
        .foregroundStyle(Palette.textSecondary)
    }

    // MARK: - Reps (editable target, defaults to prescription)

    private func repsStepper(_ exercise: Binding<ExerciseLog>) -> some View {
        HStack(spacing: 6) {
            Button {
                exercise.wrappedValue.reps = max(0, exercise.wrappedValue.reps - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
            }
            Text("\(exercise.wrappedValue.reps)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 18)
            Button {
                exercise.wrappedValue.reps += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.background.opacity(0.5)))
        .overlay(Capsule().stroke(Palette.surfaceStroke, lineWidth: 1))
    }

    // MARK: - Skip

    private func skipToggle(_ exercise: Binding<ExerciseLog>) -> some View {
        Button {
            exercise.wrappedValue.skipped.toggle()
            if exercise.wrappedValue.skipped {
                exercise.wrappedValue.setsDone = 0
            }
        } label: {
            Text(exercise.wrappedValue.skipped ? "Skipped" : "Skip")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(exercise.wrappedValue.skipped ? Palette.waived : Palette.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.background.opacity(0.5)))
        .overlay(Capsule().stroke(exercise.wrappedValue.skipped ? Palette.waived.opacity(0.4) : Palette.surfaceStroke, lineWidth: 1))
    }
}

// MARK: - Workout Session Detail (shown when a bar is tapped)

/// Gym's equivalent of SelectedBarDetail — shows the actual logged
/// exercises for the tapped day instead of a single total. `session` is
/// nil for rest days or days before this feature shipped.
struct WorkoutSessionDetail: View {
    let dateText: String
    let session: WorkoutSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dateText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)

                Spacer()

                if let session {
                    Text(session.split.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Palette.open)
                }
            }

            if let session {
                VStack(spacing: 6) {
                    ForEach(session.exercises) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(.caption)
                                .foregroundStyle(exercise.skipped ? Palette.textTertiary : Palette.textPrimary)
                                .strikethrough(exercise.skipped)

                            Spacer(minLength: 8)

                            if exercise.skipped {
                                Text("Skipped")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.waived)
                            } else {
                                Text("\(exercise.setsDone)×\(exercise.reps)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            } else {
                Text("No session logged this day")
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.surfaceStroke, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
