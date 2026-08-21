//
//  StreakManager.swift
//  LockIn
//
//  Created by kalyan cherukuru on 21/08/26.
//


import Combine
import Foundation

/// Tracks consecutive-day completion streaks for each daily goal.
///
/// A streak only advances the first time `recordCompletion(for:)` is called
/// on a given day, and only counts as "current" for display if it was last
/// extended today or yesterday — an older streak reads as broken (0) even
/// though the stored value isn't overwritten until the category is
/// completed again.
@MainActor
final class StreakManager: ObservableObject {
    static let shared = StreakManager()

    enum Category: String, CaseIterable {
        case steps
        case gym
        case leetcode
    }

    struct Streak {
        var current: Int = 0
        var best: Int = 0
    }

    @Published private(set) var streaks: [Category: Streak] = [:]

    private let userDefaults = UserDefaults.standard

    private init() {
        for category in Category.allCases {
            streaks[category] = Streak(
                current: userDefaults.integer(forKey: currentKey(for: category)),
                best: userDefaults.integer(forKey: bestKey(for: category))
            )
        }
    }

    // MARK: - Public API

    /// The streak to display: 0 if it wasn't extended today or yesterday,
    /// even if a nonzero value is still stored.
    func currentStreak(for category: Category) -> Int {
        guard let lastDate = userDefaults.string(forKey: lastDateKey(for: category)) else {
            return 0
        }

        let today = todayDateString()
        guard lastDate == today || isYesterday(lastDate, relativeTo: today) else {
            return 0
        }

        return streaks[category]?.current ?? 0
    }

    func bestStreak(for category: Category) -> Int {
        streaks[category]?.best ?? 0
    }

    /// Call whenever a category's daily goal is met. Safe to call multiple
    /// times a day — only the first call each day advances the streak.
    func recordCompletion(for category: Category) {
        let today = todayDateString()
        let lastDate = userDefaults.string(forKey: lastDateKey(for: category))

        guard lastDate != today else { return }

        var streak = streaks[category] ?? Streak()

        if let lastDate, isYesterday(lastDate, relativeTo: today) {
            streak.current += 1
        } else {
            streak.current = 1
        }

        streak.best = max(streak.best, streak.current)
        streaks[category] = streak

        userDefaults.set(today, forKey: lastDateKey(for: category))
        userDefaults.set(streak.current, forKey: currentKey(for: category))
        userDefaults.set(streak.best, forKey: bestKey(for: category))
    }

    // MARK: - Persistence Keys

    private func currentKey(for category: Category) -> String {
        AppConfig.DefaultsKey.streakCurrentPrefix + category.rawValue
    }

    private func bestKey(for category: Category) -> String {
        AppConfig.DefaultsKey.streakBestPrefix + category.rawValue
    }

    private func lastDateKey(for category: Category) -> String {
        AppConfig.DefaultsKey.streakLastDatePrefix + category.rawValue
    }

    // MARK: - Date Helpers

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func isYesterday(_ dateString: String, relativeTo todayString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: dateString),
              let today = formatter.date(from: todayString),
              let yesterday = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: today)
        else { return false }

        return Calendar(identifier: .gregorian).isDate(date, inSameDayAs: yesterday)
    }
}