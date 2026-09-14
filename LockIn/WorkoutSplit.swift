import Foundation

// MARK: - Workout Split Program

/// The fixed 3-day push/pull/legs program. Editable here — this is the
/// single source of truth for what's prescribed. Rotation (not weekday)
/// decides what's next, so a skipped day never throws the cycle out of
/// sync with the calendar.
enum WorkoutSplit: String, CaseIterable, Codable {
    case push, pull, legs

    var title: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        }
    }

    var next: WorkoutSplit {
        switch self {
        case .push: .pull
        case .pull: .legs
        case .legs: .push
        }
    }

    var exercises: [ExercisePrescription] {
        switch self {
        case .push:
            [
                ExercisePrescription(name: "Bench Press", sets: 5, reps: 5),
                ExercisePrescription(name: "Overhead Shoulder Press", sets: 3, reps: 5),
                ExercisePrescription(name: "Dips / Pushups", sets: 3, reps: 8),
                ExercisePrescription(name: "Lateral Raises", sets: 2, reps: 12),
            ]
        case .pull:
            [
                ExercisePrescription(name: "Deadlift", sets: 5, reps: 5),
                ExercisePrescription(name: "Pull Ups / Lat Pulldown", sets: 3, reps: 6),
                ExercisePrescription(name: "Barbell Row", sets: 3, reps: 5),
                ExercisePrescription(name: "Rear Delt Raises", sets: 2, reps: 12),
            ]
        case .legs:
            [
                ExercisePrescription(name: "Squats", sets: 5, reps: 5),
                ExercisePrescription(name: "Romanian Deadlift", sets: 3, reps: 6),
                ExercisePrescription(name: "Leg Press", sets: 3, reps: 10),
                ExercisePrescription(name: "Plank", sets: 3, reps: 40), // seconds — kept as a plain number for now
            ]
        }
    }
}

struct ExercisePrescription: Identifiable, Codable {
    var id: String {
        name
    }

    let name: String
    let sets: Int
    let reps: Int
}

/// What was actually logged for one exercise — starts out equal to the
/// prescription (the "assume I did it as planned" default) and is
/// editable in GymChecklist before checkout.
struct ExerciseLog: Identifiable, Codable {
    var id: String {
        name
    }

    let name: String
    var reps: Int // per set — defaults to prescription, editable
    var setsDone: Int // starts at 0, incremented during the session
    var skipped: Bool = false
}

/// One completed session: which split, and what was actually logged.
/// Persisted to Keychain keyed by date — same durability tier as the
/// per-day seconds history, since losing past workout detail on
/// reinstall would be a real loss, not just cosmetic.
struct WorkoutSession: Codable {
    let split: WorkoutSplit
    let exercises: [ExerciseLog]
}
