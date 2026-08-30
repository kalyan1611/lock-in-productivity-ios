import Combine
import Foundation

final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()

    private init() {
        waiveOffStatus = Self.loadCachedWaiveOffStatus()
    }

    enum ConnectionStatus {
        case unknown
        case online
        case offline
    }

    private let esp32BaseURL = AppConfig.Gate.baseURL
    private var apiKey: String {
        UserDefaults.standard.string(forKey: AppConfig.DefaultsKey.esp32APIKeyOverride)
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

    // Credit system (driven by sendSync() and claim())
    @Published var goalsFullyMet: Bool?
    @Published var potentialMinutesToday: Int?
    @Published var claimedMinutesToday: Int?
    @Published var availableToClaimMinutes: Int?
    @Published var remainingMinutesToday: Int?

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

    /// Backing store for `waiveOffStatus`. Every successful assignment is
    /// mirrored to UserDefaults; nothing is ever cleared just because a
    /// network call failed, so the UI keeps showing the last known-good
    /// state while offline.
    @Published var waiveOffStatus: WaiveOffStatus? {
        didSet {
            guard let waiveOffStatus else { return }
            Self.cacheWaiveOffStatus(waiveOffStatus)
        }
    }

    @Published var waiveOffFetchError: String?

    private static let waiveOffCacheKey = AppConfig.DefaultsKey.waiveOffStatusCache

    /// Wraps a cached status with the calendar day it was written on, so a
    /// stale cache from a previous day doesn't masquerade as "today."
    private struct CachedWaiveOffStatus: Codable {
        let status: WaiveOffStatus
        let cachedAt: Date
    }

    private static func loadCachedWaiveOffStatus() -> WaiveOffStatus? {
        guard let data = UserDefaults.standard.data(forKey: waiveOffCacheKey),
              let cached = try? JSONDecoder().decode(CachedWaiveOffStatus.self, from: data)
        else {
            return nil
        }

        guard Calendar.current.isDateInToday(cached.cachedAt) else {
            // The cache is from a previous day. "Waived today" no longer means
            // anything, so don't show it as still active — but the weekly
            // remaining counts are still our best guess until the next sync.
            return WaiveOffStatus(
                gymRemaining: cached.status.gymRemaining,
                stepsRemaining: cached.status.stepsRemaining,
                leetcodeRemaining: cached.status.leetcodeRemaining,
                gymWaivedToday: false,
                stepsWaivedToday: false,
                leetcodeWaivedToday: false,
                weekStart: cached.status.weekStart
            )
        }

        return cached.status
    }

    private static func cacheWaiveOffStatus(_ status: WaiveOffStatus) {
        let wrapped = CachedWaiveOffStatus(status: status, cachedAt: Date())
        guard let data = try? JSONEncoder().encode(wrapped) else { return }
        UserDefaults.standard.set(data, forKey: waiveOffCacheKey)
    }

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
        let goalsFullyMet: Bool?
        let potentialMinutesToday: Int?
        let claimedMinutesToday: Int?
        let availableToClaimMinutes: Int?
        let remainingMinutesToday: Int?
    }

    struct ClaimResult: Decodable {
        let status: String
        let justClaimedMinutes: Int
        let claimedMinutesToday: Int
        let availableToClaimMinutes: Int
        let remainingMinutesToday: Int
        let isGateOpen: Bool
        let goalsFullyMet: Bool
    }

    @discardableResult
    @MainActor
    func sendSync(steps: Int, gymSeconds: Int, leetCodeEasy: Int, leetCodeMedium: Int, leetCodeHard: Int) async throws -> SyncResult {
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
            "leetCodeEasy": leetCodeEasy,
            "leetCodeMedium": leetCodeMedium,
            "leetCodeHard": leetCodeHard,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
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
            goalsFullyMet = result.goalsFullyMet
            potentialMinutesToday = result.potentialMinutesToday
            claimedMinutesToday = result.claimedMinutesToday
            availableToClaimMinutes = result.availableToClaimMinutes
            remainingMinutesToday = result.remainingMinutesToday

            return result
        } catch {
            isGateOpen = nil
            throw error
        }
    }

    /// Locks in everything currently available (per the last sync) into
    /// today's spendable balance.
    @discardableResult
    @MainActor
    func claim() async throws -> ClaimResult {
        guard let url = URL(string: esp32BaseURL + AppConfig.Gate.claimPath) else {
            throw SyncError(message: "Invalid ESP32 address")
        }

        var request = URLRequest(url: url)
        request.httpMethod = AppConfig.Gate.Method.post
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = AppConfig.Gate.requestTimeout

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

        let result = try JSONDecoder().decode(ClaimResult.self, from: data)
        isGateOpen = result.isGateOpen
        goalsFullyMet = result.goalsFullyMet
        claimedMinutesToday = result.claimedMinutesToday
        availableToClaimMinutes = result.availableToClaimMinutes
        remainingMinutesToday = result.remainingMinutesToday

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

            guard (200 ... 299).contains(http.statusCode) else {
                waiveOffFetchError = "Gate controller returned HTTP \(http.statusCode) — is the firmware updated?"
                return
            }

            do {
                // Only overwrite on a successful decode. Any earlier value
                // (from this session or the on-disk cache) stays put on failure.
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
        guard (200 ... 299).contains(http.statusCode) else {
            throw SyncError(message: "ESP32 returned a non-success status")
        }
        let status = try JSONDecoder().decode(WaiveOffStatus.self, from: data)
        waiveOffStatus = status
        return status
    }
}
