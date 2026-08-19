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
            let uniqueSlugs = Array(Set(todaySubmissions.map { $0.titleSlug }))

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
