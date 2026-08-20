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

    private let esp32BaseURL = AppConfig.Gate.baseURL
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: AppConfig.DefaultsKey.esp32APIKeyOverride)
            ?? AppConfig.Gate.defaultAPIKey
    }

    // Gate Controller online status (Driven strictly by checkStatus())
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastCheckedAt: Date?

    /// Internet Access verdict (Driven strictly by sendSync())
    @Published var isGateOpen: Bool?

    @Published var stepGoalMet: Bool?
    @Published var gymGoalMet: Bool?
    @Published var leetCodeGoalMet: Bool?
    
    enum WaiveOffType: String { case gym, steps, leetcode }
    
    struct WaiveOffStatus: Decodable {
        let gymRemaining: Int
        let stepsRemaining: Int
        let leetcodeRemaining: Int
        let gymWaivedToday: Bool
        let stepsWaivedToday: Bool
        let leetcodeWaivedToday: Bool
        let weekStart: String
    }

    @Published var waiveOffStatus: WaiveOffStatus?
    @Published var waiveOffFetchError: String?

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
        guard let url = URL(string: esp32BaseURL + AppConfig.Gate.syncPath) else {
            throw SyncError(message: "Invalid ESP32 address")
        }

        var request = URLRequest(url: url)
        request.httpMethod = AppConfig.Gate.Method.post
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = AppConfig.Gate.requestTimeout

        let payload: [String: Int] = [
            "steps": steps,
            "gymSeconds": gymSeconds,
            "leetCodeSolved": leetCodeSolved,
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
        guard let url = URL(string: esp32BaseURL + AppConfig.Gate.statusPath) else {
            connectionStatus = .offline
            lastCheckedAt = Date()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = AppConfig.Gate.Method.get
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = AppConfig.Gate.requestTimeout

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
    
    @MainActor
    func fetchWaiveOffStatus() async {
        guard let url = URL(string: esp32BaseURL + AppConfig.Gate.waiveoffStatusPath) else {
            waiveOffFetchError = "Invalid ESP32 address"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = AppConfig.Gate.Method.get
        request.timeoutInterval = AppConfig.Gate.requestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                waiveOffFetchError = "Invalid response from ESP32"
                return
            }

            guard (200...299).contains(http.statusCode) else {
                waiveOffFetchError = "Gate controller returned HTTP \(http.statusCode) — is the firmware updated?"
                return
            }

            do {
                waiveOffStatus = try JSONDecoder().decode(WaiveOffStatus.self, from: data)
                waiveOffFetchError = nil
            } catch {
                waiveOffFetchError = "Couldn't decode waive-off response: \(error.localizedDescription)"
            }
        } catch {
            waiveOffFetchError = "Couldn't reach gate controller: \(error.localizedDescription)"
        }
    }

    @discardableResult
    @MainActor
    func useWaiveOff(_ type: WaiveOffType) async throws -> WaiveOffStatus {
        guard let url = URL(string: esp32BaseURL + AppConfig.Gate.waiveoffPath) else {
            throw SyncError(message: "Invalid ESP32 address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = AppConfig.Gate.Method.post
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = AppConfig.Gate.requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: ["type": type.rawValue])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError(message: "Invalid response from ESP32")
        }
        if http.statusCode == 409 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Waive-off unavailable"
            throw SyncError(message: msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SyncError(message: "ESP32 returned a non-success status")
        }
        let status = try JSONDecoder().decode(WaiveOffStatus.self, from: data)
        waiveOffStatus = status
        return status
    }
}
