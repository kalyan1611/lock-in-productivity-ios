import Combine
import Foundation

/// Sends step counts and gym duration to the ESP32 over the local network,
/// and tracks reachability and gate status.
final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    private init() {}

    enum ConnectionStatus {
        case unknown
        case online
        case offline
    }

    private let esp32BaseURL = "http://192.168.1.14"
    /// Secure pre-shared API key to restrict access to authorized clients only
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "esp32APIKey") ?? "garmo9-syhgAv-mytxun"
    }

    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastCheckedAt: Date?

    /// Overall goal verdict from ESP32
    @Published var goalMet: Bool?

    /// Individual gate statuses
    @Published var stepGoalMet: Bool?
    @Published var gymGoalMet: Bool?

    struct SyncError: Error, LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    struct SyncResult: Decodable {
        let status: String
        let steps: Int
        let gymSeconds: Int
        let stepGoalMet: Bool
        let gymGoalMet: Bool
        let goalMet: Bool
        let fullInternetUnlocked: Bool
    }

    struct StatusResult: Decodable {
        let today: String
        let steps: Int
        let stepGoal: Int
        let gymSeconds: Int
        let gymGoalSeconds: Int
        let stepGoalMet: Bool
        let gymGoalMet: Bool
        let overallGoalMet: Bool
        let withinAllowedHours: Bool
        let fullInternetUnlocked: Bool
    }

    private func baseURL() throws -> String {
        return esp32BaseURL
    }

    /// Sends current steps and accumulated gym seconds to POST /sync with API Key authentication
    @discardableResult
    @MainActor
    func sendSync(steps: Int, gymSeconds: Int) async throws -> SyncResult {
        let base = try baseURL()
        guard let url = URL(string: base + "/sync") else {
            throw SyncError(message: "Invalid ESP32 address")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Secure header to restrict access to authorized iOS app only
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        request.timeoutInterval = 3

        let payload: [String: Int] = [
            "steps": steps,
            "gymSeconds": gymSeconds,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncError(message: "Invalid response from ESP32")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                connectionStatus = .offline
                lastCheckedAt = Date()
                throw SyncError(message: "Unauthorized: Invalid ESP32 API Key")
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                connectionStatus = .offline
                lastCheckedAt = Date()
                throw SyncError(message: "ESP32 returned a non-success status")
            }

            connectionStatus = .online
            lastCheckedAt = Date()

            let result = try JSONDecoder().decode(SyncResult.self, from: data)
            goalMet = result.goalMet
            stepGoalMet = result.stepGoalMet
            gymGoalMet = result.gymGoalMet

            return result
        } catch {
            connectionStatus = .offline
            lastCheckedAt = Date()
            throw error
        }
    }

    /// Lightweight ping check against GET /status with API Key authentication
    @MainActor
    func checkStatus() async {
        do {
            let base = try baseURL()
            guard let url = URL(string: base + "/status") else {
                connectionStatus = .offline
                lastCheckedAt = Date()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            // Secure header to restrict access
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

            request.timeoutInterval = 3

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                connectionStatus = .offline
                lastCheckedAt = Date()
                return
            }

            connectionStatus = .online
            if let decoded = try? JSONDecoder().decode(StatusResult.self, from: data) {
                goalMet = decoded.overallGoalMet
                stepGoalMet = decoded.stepGoalMet
                gymGoalMet = decoded.gymGoalMet
            }
        } catch {
            connectionStatus = .offline
        }
        lastCheckedAt = Date()
    }
}
