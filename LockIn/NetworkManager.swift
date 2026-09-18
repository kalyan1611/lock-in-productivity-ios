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
        #if DEBUG
            // Never write debug/seeded progress into the real ESP32's ledger —
            // see DebugGateSimulator below. Everything published here mirrors
            // exactly what a real /sync response would set.
            debugSync(steps: steps, gymSeconds: gymSeconds, leetCodeEasy: leetCodeEasy, leetCodeMedium: leetCodeMedium, leetCodeHard: leetCodeHard)
            return SyncResult(
                status: "debug",
                steps: steps,
                gymSeconds: gymSeconds,
                leetCodeSolved: leetCodeEasy + leetCodeMedium + leetCodeHard,
                stepGoalMet: stepGoalMet ?? false,
                gymGoalMet: gymGoalMet ?? false,
                leetCodeGoalMet: leetCodeGoalMet,
                isGateOpen: isGateOpen ?? false,
                goalsFullyMet: goalsFullyMet,
                potentialMinutesToday: potentialMinutesToday,
                claimedMinutesToday: claimedMinutesToday,
                availableToClaimMinutes: availableToClaimMinutes,
                remainingMinutesToday: remainingMinutesToday
            )
        #else
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
        #endif
    }

    /// Locks in everything currently available (per the last sync) into
    /// today's spendable balance.
    @discardableResult
    @MainActor
    func claim(minutes: Int? = nil) async throws -> ClaimResult {
        #if DEBUG
            let before = claimedMinutesToday ?? 0
            debugClaim()
            let after = claimedMinutesToday ?? 0
            return ClaimResult(
                status: "debug",
                justClaimedMinutes: max(after - before, 0),
                claimedMinutesToday: after,
                availableToClaimMinutes: availableToClaimMinutes ?? 0,
                remainingMinutesToday: remainingMinutesToday ?? 0,
                isGateOpen: isGateOpen ?? false,
                goalsFullyMet: goalsFullyMet ?? false
            )
        #else
            guard let url = URL(string: esp32BaseURL + AppConfig.Gate.claimPath) else {
                throw SyncError(message: "Invalid ESP32 address")
            }

            var request = URLRequest(url: url)
            request.httpMethod = AppConfig.Gate.Method.post
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = AppConfig.Gate.requestTimeout

            if let minutes {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["minutes": minutes])
            }

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
        #endif
    }

    /// Lightweight ping check determining Gate Controller online status
    /// strictly via GET /status. Read-only — safe to keep real even in
    /// DEBUG, since there's nothing here to corrupt.
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
        #if DEBUG
            // debugSync/debugUseWaiveOff already keep waiveOffStatus current —
            // fetching the real gate's status here would immediately clobber
            // the local simulation with production data.
            return
        #else
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
        #endif
    }

    @discardableResult
    @MainActor
    func useWaiveOff(_ type: WaiveOffType) async throws -> WaiveOffStatus {
        #if DEBUG
            try debugUseWaiveOff(type)
            guard let status = waiveOffStatus else {
                throw SyncError(message: "Debug waive-off state missing")
            }
            return status
        #else
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
        #endif
    }
}

#if DEBUG

    // MARK: - DEBUG: Local Gate Simulation

    /// Mirrors CreditEngine.cpp's math closely enough for realistic
    /// GateHero/waive-off UI testing — NOT a byte-for-byte port, and doesn't
    /// simulate restricted-domain usage decay (chargeRestrictedUsage() fires
    /// server-side when a phone actually hits a blocked domain through the
    /// gate; the app has no visibility into that, so remainingMinutesToday
    /// just tracks claimedMinutesToday with no drain). State lives in
    /// UserDefaults, day/week-scoped, and never touches the real ESP32.
    private enum DebugCredit {
        static let baselineMinutes = 60
        static let stepsPerChunk = 1000
        static let minutesPerStepChunk = 10
        static let maxMinutesFromSteps = 100
        static let gymBonusMinutes = 45
        static let leetEasyMinutes = 5
        static let leetMediumMinutes = 10
        static let leetHardMinutes = 15
        static let maxMinutesFromLeetCode = 150

        static let gymWaiveoffMax = 3
        static let stepsWaiveoffMax = 2
        static let leetcodeWaiveoffMax = 2
    }

    private struct DebugGateState: Codable {
        var date: String
        var claimedMinutesToday: Int
        var weekStart: String
        var gymRemaining: Int
        var stepsRemaining: Int
        var leetcodeRemaining: Int
        var gymWaivedToday: Bool
        var stepsWaivedToday: Bool
        var leetcodeWaivedToday: Bool
    }

    extension NetworkManager {
        private static let debugStateKey = "LockIn_Debug_GateState"

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

        private func loadDebugState() -> DebugGateState {
            let today = Self.dayString(Date())
            let weekStart = Self.weekStartString(Date())

            if let data = UserDefaults.standard.data(forKey: Self.debugStateKey),
               var state = try? JSONDecoder().decode(DebugGateState.self, from: data)
            {
                if state.weekStart != weekStart {
                    state.weekStart = weekStart
                    state.gymRemaining = DebugCredit.gymWaiveoffMax
                    state.stepsRemaining = DebugCredit.stepsWaiveoffMax
                    state.leetcodeRemaining = DebugCredit.leetcodeWaiveoffMax
                }
                if state.date != today {
                    state.date = today
                    state.claimedMinutesToday = 0
                    state.gymWaivedToday = false
                    state.stepsWaivedToday = false
                    state.leetcodeWaivedToday = false
                }
                return state
            }

            return DebugGateState(
                date: today,
                claimedMinutesToday: 0,
                weekStart: weekStart,
                gymRemaining: DebugCredit.gymWaiveoffMax,
                stepsRemaining: DebugCredit.stepsWaiveoffMax,
                leetcodeRemaining: DebugCredit.leetcodeWaiveoffMax,
                gymWaivedToday: false,
                stepsWaivedToday: false,
                leetcodeWaivedToday: false
            )
        }

        private func saveDebugState(_ state: DebugGateState) {
            guard let data = try? JSONEncoder().encode(state) else { return }
            UserDefaults.standard.set(data, forKey: Self.debugStateKey)
        }

        private func publishWaiveOffStatus(_ state: DebugGateState) {
            waiveOffStatus = WaiveOffStatus(
                gymRemaining: state.gymRemaining,
                stepsRemaining: state.stepsRemaining,
                leetcodeRemaining: state.leetcodeRemaining,
                gymWaivedToday: state.gymWaivedToday,
                stepsWaivedToday: state.stepsWaivedToday,
                leetcodeWaivedToday: state.leetcodeWaivedToday,
                weekStart: state.weekStart
            )
            waiveOffFetchError = nil
        }

        /// DEBUG stand-in for POST /sync.
        @MainActor
        func debugSync(steps: Int, gymSeconds: Int, leetCodeEasy: Int, leetCodeMedium: Int, leetCodeHard: Int) {
            let state = loadDebugState()

            let stepMet = steps >= AppConfig.Steps.dailyTarget || state.stepsWaivedToday
            let gymMet = gymSeconds >= Int(AppConfig.Gym.targetDurationSeconds) || state.gymWaivedToday
            let leetTotal = leetCodeEasy + leetCodeMedium + leetCodeHard
            let leetMet = leetTotal >= AppConfig.LeetCode.dailyTargetProblems || state.leetcodeWaivedToday
            let fullyMet = stepMet && gymMet && leetMet

            let fromSteps = state.stepsWaivedToday
                ? DebugCredit.maxMinutesFromSteps
                : min((steps / DebugCredit.stepsPerChunk) * DebugCredit.minutesPerStepChunk, DebugCredit.maxMinutesFromSteps)
            let fromGym = gymMet ? DebugCredit.gymBonusMinutes : 0
            let rawLeet = leetCodeEasy * DebugCredit.leetEasyMinutes
                + leetCodeMedium * DebugCredit.leetMediumMinutes
                + leetCodeHard * DebugCredit.leetHardMinutes
            let fromLeet = state.leetcodeWaivedToday ? DebugCredit.maxMinutesFromLeetCode : min(rawLeet, DebugCredit.maxMinutesFromLeetCode)

            let potential = DebugCredit.baselineMinutes + fromSteps + fromGym + fromLeet
            let available = max(potential - state.claimedMinutesToday, 0)

            saveDebugState(state)

            stepGoalMet = stepMet
            gymGoalMet = gymMet
            leetCodeGoalMet = leetMet
            goalsFullyMet = fullyMet
            potentialMinutesToday = potential
            claimedMinutesToday = state.claimedMinutesToday
            availableToClaimMinutes = available
            remainingMinutesToday = state.claimedMinutesToday
            isGateOpen = fullyMet || state.claimedMinutesToday > 0

            publishWaiveOffStatus(state)
        }

        /// DEBUG stand-in for POST /claim.
        @MainActor
        func debugClaim() {
            var state = loadDebugState()
            let potential = potentialMinutesToday ?? state.claimedMinutesToday
            if potential > state.claimedMinutesToday {
                state.claimedMinutesToday = potential
            }
            saveDebugState(state)

            claimedMinutesToday = state.claimedMinutesToday
            availableToClaimMinutes = 0
            remainingMinutesToday = state.claimedMinutesToday
            isGateOpen = (goalsFullyMet ?? false) || state.claimedMinutesToday > 0
        }

        /// DEBUG stand-in for POST /waiveoff.
        @MainActor
        func debugUseWaiveOff(_ type: WaiveOffType) throws {
            var state = loadDebugState()
            switch type {
            case .gym:
                guard state.gymRemaining > 0 else { throw SyncError(message: "No gym waive-offs left this week") }
                guard !state.gymWaivedToday else { throw SyncError(message: "Already waived today") }
                state.gymRemaining -= 1
                state.gymWaivedToday = true
            case .steps:
                guard state.stepsRemaining > 0 else { throw SyncError(message: "No step waive-offs left this week") }
                guard !state.stepsWaivedToday else { throw SyncError(message: "Already waived today") }
                state.stepsRemaining -= 1
                state.stepsWaivedToday = true
            case .leetcode:
                guard state.leetcodeRemaining > 0 else { throw SyncError(message: "No LeetCode waive-offs left this week") }
                guard !state.leetcodeWaivedToday else { throw SyncError(message: "Already waived today") }
                state.leetcodeRemaining -= 1
                state.leetcodeWaivedToday = true
            }
            saveDebugState(state)
            publishWaiveOffStatus(state)
        }
    }
#endif
