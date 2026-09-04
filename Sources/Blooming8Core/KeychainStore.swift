import Foundation
import Security

/// Minimal Keychain wrapper for the one thing this app needs from it:
/// storing a small string (a password hash) under a fixed service+account,
/// instead of in a UserDefaults-backed plist under ~/Library/Preferences —
/// which, since neither product is sandboxed, is readable by any process
/// running as this user with no entitlement or prompt required at all.
///
/// No `kSecAttrAccessGroup` is set — that needs an App Groups entitlement,
/// which needs a paid Developer ID signing identity, which this project
/// deliberately doesn't have (see `AppSettings.suiteName`'s own comment on
/// why it uses a plain UserDefaults suite instead of a real App Group for
/// the same reason). Without a shared access group, Keychain items are
/// scoped per-app: the widget and the windowed app do NOT see each other's
/// entries here, unlike the shared UserDefaults suite everything else uses.
enum KeychainStore {
    private static let service = "com.pholtom.blooming8"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // This device only, not synced via iCloud Keychain; readable
            // once the user has unlocked the Mac at least once since boot —
            // matches a background app that isn't running before login.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
