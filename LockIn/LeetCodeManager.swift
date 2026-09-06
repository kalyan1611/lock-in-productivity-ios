import Combine
import Foundation
import SwiftUI

@MainActor
final class LeetCodeManager: ObservableObject {
    static let shared = LeetCodeManager()

    // MARK: - Published State

    @Published var easyTodayCount: Int = 0
    @Published var mediumTodayCount: Int = 0
    @Published var hardTodayCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?

    @AppStorage(AppConfig.DefaultsKey.leetcodeUsername) var username: String = AppConfig.LeetCode.defaultUsername

    // MARK: - Gate Target

    let targetProblems: Int = AppConfig.LeetCode.dailyTargetProblems

    var totalTodayCount: Int {
        easyTodayCount + mediumTodayCount + hardTodayCount
    }

    var isGoalMet: Bool {
        totalTodayCount >= targetProblems
    }

    var progress: Double {
        guard targetProblems > 0 else { return 0 }
        return min(Double(totalTodayCount) / Double(targetProblems), 1.0)
    }

    private let graphqlEndpoint = URL(string: AppConfig.LeetCode.graphqlEndpoint)!

    // MARK: - Local History Persistence
    //
    // LeetCode's public GraphQL only exposes a rolling "recent submissions"
    // list, not calendar-bucketed history — unlike HealthKit (steps) or our
    // own UserDefaults log (gym), there's no backdated history to read.
    // Interim fix: cache each day's total locally, same pattern GymTracker
    // uses, so Week/Month charts start accumulating real data from today
    // forward. Full backdated history needs LeetCode's submission-calendar
    // endpoint (tracked separately).

    private let dailyCountKeyPrefix = AppConfig.DefaultsKey.leetcodeDailyCountPrefix
    private let userDefaults = UserDefaults.standard

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Difficulty breakdown keys
    //
    // The original cache only stored the day's total, which was enough for
    // a single-color bar. The stacked chart needs each difficulty's count
    // too, so we additionally cache easy/medium/hard under their own keys.
    // Days recorded before this shipped will read back 0 for the
    // breakdown even though their total is real — same "honest gap"
    // philosophy as the rest of this cache.

    private func easyKey(_ date: Date) -> String {
        dailyCountKeyPrefix + AppConfig.DefaultsKey.leetcodeEasySuffix + dateString(date)
    }
    private func mediumKey(_ date: Date) -> String {
        dailyCountKeyPrefix + AppConfig.DefaultsKey.leetcodeMediumSuffix + dateString(date)
    }
    private func hardKey(_ date: Date) -> String {
        dailyCountKeyPrefix + AppConfig.DefaultsKey.leetcodeHardSuffix + dateString(date)
    }

    struct DailyBreakdown {
        let date: Date
        let easy: Int
        let medium: Int
        let hard: Int
    }

    /// Persists today's total (and difficulty breakdown) under today's date
    /// key. Called after every successful fetch so the log stays current
    /// without needing a separate write path.
    private func recordTodayCount() {
        let today = Date()
        userDefaults.set(totalTodayCount, forKey: dailyCountKeyPrefix + dateString(today))
        userDefaults.set(easyTodayCount, forKey: easyKey(today))
        userDefaults.set(mediumTodayCount, forKey: mediumKey(today))
        userDefaults.set(hardTodayCount, forKey: hardKey(today))
    }

    /// Last `days` calendar days of solved-problem totals, oldest first.
    /// Days before this feature shipped (or before the user first opened
    /// the app on a given day) simply read back 0 — there's no synthetic
    /// backfill, so the chart honestly reflects what's actually known.
    func history(days: Int) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var result: [(date: Date, count: Int)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = dailyCountKeyPrefix + dateString(day)
            let count = userDefaults.integer(forKey: key)
            result.append((date: calendar.startOfDay(for: day), count: count))
        }
        return result
    }

    /// Same window as `history(days:)`, but with the easy/medium/hard split
    /// needed to render a stacked bar.
    func breakdownHistory(days: Int) -> [DailyBreakdown] {
        let calendar = Calendar.current
        var result: [DailyBreakdown] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            result.append(DailyBreakdown(
                date: calendar.startOfDay(for: day),
                easy: userDefaults.integer(forKey: easyKey(day)),
                medium: userDefaults.integer(forKey: mediumKey(day)),
                hard: userDefaults.integer(forKey: hardKey(day))
            ))
        }
        return result
    }

    /// True once at least one day older than today has a real recorded
    /// value — used to decide whether to show the "history is still
    /// building" note under the chart.
    func hasMultiDayHistory() -> Bool {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return false }
        let key = dailyCountKeyPrefix + dateString(yesterday)
        return userDefaults.object(forKey: key) != nil
    }

    // MARK: - Fetch Today's Stats

    func fetchTodaySolvedProblems() async {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else {
            errorMessage = "Username empty"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Fetch recent AC submissions
            let submissions = try await fetchRecentACSubmissions(username: trimmedUser)

            // 2. Filter for today's submissions
            let calendar = Calendar.current
            let todaySubmissions = submissions.filter { sub in
                guard let timestampSec = Double(sub.timestamp) else { return false }
                let date = Date(timeIntervalSince1970: timestampSec)
                return calendar.isDateInToday(date)
            }

            // Deduplicate unique solved problems today
            let uniqueSlugs = Array(Set(todaySubmissions.map(\.titleSlug)))

            // 3. Concurrently fetch difficulty for today's unique problems
            var easy = 0
            var medium = 0
            var hard = 0

            try await withThrowingTaskGroup(of: String.self) { group in
                for slug in uniqueSlugs {
                    group.addTask {
                        try await self.fetchProblemDifficulty(titleSlug: slug)
                    }
                }

                for try await difficulty in group {
                    switch difficulty.lowercased() {
                    case "easy": easy += 1
                    case "medium": medium += 1
                    case "hard": hard += 1
                    default: break
                    }
                }
            }

            easyTodayCount = easy
            mediumTodayCount = medium
            hardTodayCount = hard
            lastUpdated = Date()
            isLoading = false

            recordTodayCount()
        } catch {
            errorMessage = "Failed to update LeetCode data"
            isLoading = false
        }
    }

    // MARK: - GraphQL API Calls

    private struct ACSubmission: Decodable {
        let id: String
        let title: String
        let titleSlug: String
        let timestamp: String
    }

    private struct RecentACResponse: Decodable {
        struct DataClass: Decodable {
            let recentAcSubmissionList: [ACSubmission]?
        }

        let data: DataClass?
    }

    private func fetchRecentACSubmissions(username: String) async throws -> [ACSubmission] {
        let query = """
        query recentAcSubmissions($username: String!, $limit: Int!) {
            recentAcSubmissionList(username: $username, limit: $limit) {
                id
                title
                titleSlug
                timestamp
            }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": ["username": username, "limit": 50],
        ]

        var request = URLRequest(url: graphqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(RecentACResponse.self, from: data)
        return decoded.data?.recentAcSubmissionList ?? []
    }

    private struct QuestionResponse: Decodable {
        struct DataClass: Decodable {
            struct Question: Decodable {
                let difficulty: String?
            }

            let question: Question?
        }

        let data: DataClass?
    }

    private func fetchProblemDifficulty(titleSlug: String) async throws -> String {
        let query = """
        query getQuestionDifficulty($titleSlug: String!) {
            question(titleSlug: $titleSlug) {
                difficulty
            }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": ["titleSlug": titleSlug],
        ]

        var request = URLRequest(url: graphqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return "Unknown"
        }

        let decoded = try JSONDecoder().decode(QuestionResponse.self, from: data)
        return decoded.data?.question?.difficulty ?? "Unknown"
    }
}
