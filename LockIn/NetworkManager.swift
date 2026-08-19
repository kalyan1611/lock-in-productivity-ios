import Combine
import Foundation

final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    private init() {}

    enum ConnectionStatus {
        case unknown
        case online
        case offline
    }

    private let esp32BaseURL = "http://192.168.1.14"
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "esp32APIKey") ?? "garmo9-syhgAv-mytxun"
    }

    // Gate Controller online status (Driven strictly by checkStatus())
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastCheckedAt: Date?

    // Internet Access verdict (Driven strictly by sendSync())
    @Published var isGateOpen: Bool?

    @Published var stepGoalMet: Bool?
    @Published var gymGoalMet: Bool?
    @Published var leetCodeGoalMet: Bool?

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
        let leetCodeSolved: Int?
        let stepGoalMet: Bool
        let gymGoalMet: Bool
        let leetCodeGoalMet: Bool?
        let isGateOpen: Bool
    }

    @discardableResult
    @MainActor
    func sendSync(steps: Int, gymSeconds: Int, leetCodeSolved: Int) async throws -> SyncResult {
        guard let url = URL(string: esp32BaseURL + "/sync") else {
            throw SyncError(message: "Invalid ESP32 address")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 3

        let payload: [String: Int] = [
            "steps": steps,
            "gymSeconds": gymSeconds,
            "leetCodeSolved": leetCodeSolved
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError(message: "Invalid response from ESP32")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw SyncError(message: "Unauthorized: Invalid ESP32 API Key")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw SyncError(message: "ESP32 returned a non-success status")
        }

        let result = try JSONDecoder().decode(SyncResult.self, from: data)
        isGateOpen = result.isGateOpen
        stepGoalMet = result.stepGoalMet
        gymGoalMet = result.gymGoalMet
        leetCodeGoalMet = result.leetCodeGoalMet

        return result
    }

    /// Lightweight ping check determining Gate Controller online status strictly via GET /status
    @MainActor
    func checkStatus() async {
        guard let url = URL(string: esp32BaseURL + "/status") else {
            connectionStatus = .offline
            lastCheckedAt = Date()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                connectionStatus = .offline
                lastCheckedAt = Date()
                return
            }

            connectionStatus = .online
        } catch {
            connectionStatus = .offline
        }
        lastCheckedAt = Date()
    }
}
