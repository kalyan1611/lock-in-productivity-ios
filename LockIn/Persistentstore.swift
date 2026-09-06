import Foundation
import Security

// MARK: - Keychain-Backed Persistent Store

/// Small key/value store backed by the iOS Keychain instead of UserDefaults.
///
/// UserDefaults is wiped the moment the app is uninstalled — fine for
/// session/UI state, but wrong for the gym/LeetCode daily-history caches:
/// losing those on a reinstall means the Week/Month charts silently forget
/// everything earned before that point. Keychain items are NOT removed on
/// uninstall (only an explicit `remove`, or the user wiping their device's
/// keychain, clears them), so this is a drop-in place to put anything that
/// needs to outlive the app binary itself.
///
/// Not meant to replace UserDefaults everywhere — just for the specific
/// history caches where "gone after reinstall" is actually a data-loss bug.
enum KeychainStore {
    private static let service = "com.lockin.persistent"

    private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private static func read(_ key: String) -> Data? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, forKey key: String) {
        // kSecAttrAccessibleAfterFirstUnlock (rather than the "ThisDeviceOnly"
        // variants) is what actually matters here — some Accessible options
        // get cleared on some restore paths, this one is the standard choice
        // for "small values that should just persist."
        if read(key) != nil {
            let attributes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query(for: key) as CFDictionary, attributes as CFDictionary)
        } else {
            var newItem = query(for: key)
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    static func remove(forKey key: String) {
        SecItemDelete(query(for: key) as CFDictionary)
    }

    /// Whether a value has ever been written for this key — distinct from
    /// `double`/`integer` returning their zero default, so callers can tell
    /// "explicitly zero" apart from "never recorded."
    static func exists(forKey key: String) -> Bool {
        read(key) != nil
    }

    // MARK: - Double

    static func setDouble(_ value: Double, forKey key: String) {
        write(Data(String(value).utf8), forKey: key)
    }

    static func double(forKey key: String) -> Double {
        guard let data = read(key), let string = String(data: data, encoding: .utf8) else { return 0 }
        return Double(string) ?? 0
    }

    // MARK: - Int

    static func setInt(_ value: Int, forKey key: String) {
        write(Data(String(value).utf8), forKey: key)
    }

    static func integer(forKey key: String) -> Int {
        guard let data = read(key), let string = String(data: data, encoding: .utf8) else { return 0 }
        return Int(string) ?? 0
    }

    // MARK: - String

    static func setString(_ value: String, forKey key: String) {
        write(Data(value.utf8), forKey: key)
    }

    static func string(forKey key: String) -> String? {
        guard let data = read(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
