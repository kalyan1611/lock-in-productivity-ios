//
//  WaiveOffManager.swift
//  LockIn
//
//  Created by kalyan cherukuru on 19/09/26.
//


import Foundation
import Combine

// MARK: - Waive-Off Manager

/// Local, on-device replacement for the waive-off half of the old
/// NetworkManager. Previously the ESP32 gate was the source of truth for
/// how many weekly waive-offs each goal had left and whether one had
/// already been used today; now that the app no longer talks to a gate
/// device at all, this tracks the exact same allowance entirely in
/// UserDefaults, using the same Monday-based week boundary the rest of the
/// app (DailyOutcomeStore) already uses.
///
/// Per-goal weekly limits come from `AppConfig.WaiveOff` rather than being
/// duplicated here, so this and WeeklyRetrospectiveCard's denominator can
/// never drift apart.
@MainActor
final class WaiveOffManager: ObservableObject {
    static let shared = WaiveOffManager()

    enum WaiveOffType: String, Codable {
        case gym
        case steps
        case leetcode
    }

    /// Same shape the old NetworkManager exposed, so ContentView/ActivityCard
    /// didn't need to change how they read waive-off state — only where it
    /// comes from.
    struct WaiveOffStatus: Codable {
        let gymRemaining: Int
        let stepsRemaining: Int
        let leetcodeRemaining: Int
        let gymWaivedToday: Bool
        let stepsWaivedToday: Bool
        let leetcodeWaivedToday: Bool
    }

    struct WaiveOffError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Published private(set) var waiveOffStatus: WaiveOffStatus?

    /// Persisted usage for one calendar week. `weekStart` (Monday,
    /// yyyy-MM-dd) is what lets `loadRecord()` tell "still this week" apart
    /// from "a new week started, reset the counts" — there's no rollover
    /// timer, this is just checked lazily whenever the record is read.
    private struct Record: Codable {
        var weekStart: String
        var gymUsed: Int
        var stepsUsed: Int
        var leetcodeUsed: Int
        var gymWaivedDate: String?
        var stepsWaivedDate: String?
        var leetcodeWaivedDate: String?
    }

    private init() {
        refresh()
    }

    // MARK: - Week / day boundary

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Monday of the calendar week containing `date`, as yyyy-MM-dd.
    /// Mirrors DailyOutcomeStore's week boundary exactly (tm_wday 0 = Sun
    /// ... 6 = Sat, daysSinceMonday = wday == 0 ? 6 : wday - 1 — Calendar's
    /// `weekday` is tm_wday + 1, so the rule becomes `weekday - 2`, with
    /// Sunday special-cased to 6) so both stay on the same week grid.
    private static func mondayString(for date: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        return dateFormatter.string(from: monday)
    }

    // MARK: - Persistence

    private func loadRecord() -> Record {
        let currentWeekStart = Self.mondayString(for: Date())
        if let data = UserDefaults.standard.data(forKey: AppConfig.DefaultsKey.waiveOffState),
           let record = try? JSONDecoder().decode(Record.self, from: data),
           record.weekStart == currentWeekStart
        {
            return record
        }
        // No saved record, or it's from a prior week — start this week fresh.
        return Record(
            weekStart: currentWeekStart,
            gymUsed: 0, stepsUsed: 0, leetcodeUsed: 0,
            gymWaivedDate: nil, stepsWaivedDate: nil, leetcodeWaivedDate: nil
        )
    }

    private func saveRecord(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: AppConfig.DefaultsKey.waiveOffState)
    }

    private func status(from record: Record) -> WaiveOffStatus {
        let today = Self.dateFormatter.string(from: Date())
        return WaiveOffStatus(
            gymRemaining: max(AppConfig.WaiveOff.gym - record.gymUsed, 0),
            stepsRemaining: max(AppConfig.WaiveOff.steps - record.stepsUsed, 0),
            leetcodeRemaining: max(AppConfig.WaiveOff.leetcode - record.leetcodeUsed, 0),
            gymWaivedToday: record.gymWaivedDate == today,
            stepsWaivedToday: record.stepsWaivedDate == today,
            leetcodeWaivedToday: record.leetcodeWaivedDate == today
        )
    }

    // MARK: - Public API

    /// Recomputes published status from persisted state, rolling over into
    /// a fresh week's allowance if the calendar week has changed. Safe to
    /// call as often as needed (app foreground, pull-to-refresh) — replaces
    /// the old checkStatus()/fetchWaiveOffStatus() network round-trips.
    func refresh() {
        let record = loadRecord()
        saveRecord(record) // persist the rollover if one just happened
        waiveOffStatus = status(from: record)
    }

    /// Spends one of this week's waive-offs for `type`. Throws if today's
    /// already been waived for that goal, or the week's allowance is spent.
    @discardableResult
    func useWaiveOff(_ type: WaiveOffType) throws -> WaiveOffStatus {
        var record = loadRecord()
        let today = Self.dateFormatter.string(from: Date())

        switch type {
        case .gym:
            guard record.gymWaivedDate != today else {
                throw WaiveOffError(message: "You've already used today's waive-off for this goal.")
            }
            guard record.gymUsed < AppConfig.WaiveOff.gym else {
                throw WaiveOffError(message: "No waive-offs left for this goal this week.")
            }
            record.gymUsed += 1
            record.gymWaivedDate = today

        case .steps:
            guard record.stepsWaivedDate != today else {
                throw WaiveOffError(message: "You've already used today's waive-off for this goal.")
            }
            guard record.stepsUsed < AppConfig.WaiveOff.steps else {
                throw WaiveOffError(message: "No waive-offs left for this goal this week.")
            }
            record.stepsUsed += 1
            record.stepsWaivedDate = today

        case .leetcode:
            guard record.leetcodeWaivedDate != today else {
                throw WaiveOffError(message: "You've already used today's waive-off for this goal.")
            }
            guard record.leetcodeUsed < AppConfig.WaiveOff.leetcode else {
                throw WaiveOffError(message: "No waive-offs left for this goal this week.")
            }
            record.leetcodeUsed += 1
            record.leetcodeWaivedDate = today
        }

        saveRecord(record)
        let newStatus = status(from: record)
        waiveOffStatus = newStatus
        return newStatus
    }
}
