import Combine
import Foundation

// MARK: - Waive-Off Manager

/// Local-only tracker for the limited weekly "waive-off" allowance per
/// goal — using one excuses that goal as met for the day without it
/// actually being completed.
///
/// This used to be ESP32-side state (NVS-backed, Monday-based weekly
/// reset) that the app only ever read a cached copy of. Now that the app
/// doesn't talk to any gate device, this is the sole implementation,
/// backed by UserDefaults instead — the same day/week rollover rules,
/// just local. There's no claim/credit/spendable-balance concept here:
/// that only ever made sense as spending against a gate the ESP32
/// enforced, and has no replacement now that nothing enforces anything.
@MainActor
final class WaiveOffManager: ObservableObject {
    static let shared = WaiveOffManager()

    enum WaiveOffType: String { case gym, steps, leetcode }

    struct WaiveOffStatus: Codable {
        let gymRemaining: Int
        let stepsRemaining: Int
        let leetcodeRemaining: Int
        let gymWaivedToday: Bool
        let stepsWaivedToday: Bool
        let leetcodeWaivedToday: Bool
        let weekStart: String
    }

    struct WaiveOffError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Published private(set) var waiveOffStatus: WaiveOffStatus?

    private enum WeeklyAllowance {
        static let gym = 3
        static let steps = 2
        static let leetcode = 2
    }

    private struct State: Codable {
        var date: String
        var weekStart: String
        var gymRemaining: Int
        var stepsRemaining: Int
        var leetcodeRemaining: Int
        var gymWaivedToday: Bool
        var stepsWaivedToday: Bool
        var leetcodeWaivedToday: Bool
    }

    private let userDefaults = UserDefaults.standard
    private static let stateKey = AppConfig.DefaultsKey.waiveOffState

    private init() {
        refresh()
    }

    // MARK: - Day/week bookkeeping

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekStartString(_ date: Date) -> String {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return dayString(start)
    }

    private func loadState() -> State {
        let today = Self.dayString(Date())
        let weekStart = Self.weekStartString(Date())

        if let data = userDefaults.data(forKey: Self.stateKey),
           var state = try? JSONDecoder().decode(State.self, from: data)
        {
            if state.weekStart != weekStart {
                state.weekStart = weekStart
                state.gymRemaining = WeeklyAllowance.gym
                state.stepsRemaining = WeeklyAllowance.steps
                state.leetcodeRemaining = WeeklyAllowance.leetcode
            }
            if state.date != today {
                state.date = today
                state.gymWaivedToday = false
                state.stepsWaivedToday = false
                state.leetcodeWaivedToday = false
            }
            return state
        }

        return State(
            date: today,
            weekStart: weekStart,
            gymRemaining: WeeklyAllowance.gym,
            stepsRemaining: WeeklyAllowance.steps,
            leetcodeRemaining: WeeklyAllowance.leetcode,
            gymWaivedToday: false,
            stepsWaivedToday: false,
            leetcodeWaivedToday: false
        )
    }

    private func saveState(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.stateKey)
    }

    private func publish(_ state: State) {
        waiveOffStatus = WaiveOffStatus(
            gymRemaining: state.gymRemaining,
            stepsRemaining: state.stepsRemaining,
            leetcodeRemaining: state.leetcodeRemaining,
            gymWaivedToday: state.gymWaivedToday,
            stepsWaivedToday: state.stepsWaivedToday,
            leetcodeWaivedToday: state.leetcodeWaivedToday,
            weekStart: state.weekStart
        )
    }

    // MARK: - Public API

    /// Rolls day/week state forward if the calendar has moved on since
    /// the last call, and republishes. Cheap — safe to call on every
    /// refresh (see ContentView.refresh()).
    func refresh() {
        let state = loadState()
        saveState(state)
        publish(state)
    }

    /// Spends one of this week's waive-offs for `type`, marking that
    /// goal as waived for today. Throws if none are left this week or
    /// today's already been waived.
    @discardableResult
    func useWaiveOff(_ type: WaiveOffType) throws -> WaiveOffStatus {
        var state = loadState()
        switch type {
        case .gym:
            guard state.gymRemaining > 0 else { throw WaiveOffError(message: "No gym waive-offs left this week") }
            guard !state.gymWaivedToday else { throw WaiveOffError(message: "Already waived today") }
            state.gymRemaining -= 1
            state.gymWaivedToday = true
        case .steps:
            guard state.stepsRemaining > 0 else { throw WaiveOffError(message: "No step waive-offs left this week") }
            guard !state.stepsWaivedToday else { throw WaiveOffError(message: "Already waived today") }
            state.stepsRemaining -= 1
            state.stepsWaivedToday = true
        case .leetcode:
            guard state.leetcodeRemaining > 0 else { throw WaiveOffError(message: "No LeetCode waive-offs left this week") }
            guard !state.leetcodeWaivedToday else { throw WaiveOffError(message: "Already waived today") }
            state.leetcodeRemaining -= 1
            state.leetcodeWaivedToday = true
        }

        saveState(state)
        publish(state)

        guard let status = waiveOffStatus else {
            throw WaiveOffError(message: "Waive-off state missing")
        }
        return status
    }
}