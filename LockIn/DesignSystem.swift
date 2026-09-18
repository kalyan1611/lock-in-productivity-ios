import SwiftUI

// MARK: - Design Tokens

//
// LockIn's whole premise is a physical gate that only opens when the day's
// goals are met, so the UI leans into that: a dark "control panel" surface,
// one accent color that means "open" and one that means "restricted," and a
// ring motif — each goal closes its own ring, the hero dial is the sum of
// them. Nothing here is decorative; every ring, dot, and capsule reports a
// real piece of state from GymTracker / HealthKitManager / NetworkManager.

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Palette {
    // MARK: - Backgrounds

    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x050505)
    static let surfaceRaised = Color(hex: 0x171B1F)
    static let surfaceStroke = Color(hex: 0x24292E)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xD3D8DE)
    static let textSecondary = Color(hex: 0x8A9199)
    static let textTertiary = Color(hex: 0x555C64)

    // MARK: - Semantic

    static let open = Color(hex: 0x55E6A5) // Goal met / unlocked
    static let started = Color(hex: 0x4F8FEF) // In progress
    static let locked = Color(hex: 0xFF5C5C) // Restricted
    static let waived = Color(hex: 0xE7A94B) // Waive-off used
    static let neutral = Color(hex: 0x4B525A) // Not started / inactive
}

enum Typography {
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static var eyebrow: Font {
        .system(.caption, design: .monospaced).weight(.semibold)
    }
}

// MARK: - Shared goal-color logic

// Grey: not started. Blue: started, not yet complete. Green: goal met.
// Orange: a waive-off covered the day instead. `isCompleted` wins over
// `waived` since actually meeting the goal outranks skipping it.
// Shared by StepsCard, GymCard, and LeetCodeCard so the mapping only
// lives in one place.
enum GoalColor {
    static func forProgress(_ progress: Double, isCompleted: Bool, waived: Bool) -> Color {
        if isCompleted {
            return Palette.open
        }
        if waived {
            return Palette.waived
        }
        if progress > 0 {
            return Palette.started
        }
        return Palette.neutral
    }
}

// MARK: - Shared minute formatting

/// "1h 5m" / "1h" / "45m" — used by GateHero's credit row and label.
func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h > 0, m > 0 {
        return "\(h)h \(m)m"
    }
    if h > 0 {
        return "\(h)h"
    }
    return "\(m)m"
}
