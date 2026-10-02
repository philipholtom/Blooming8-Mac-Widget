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
///
/// **Access control.** Items are stored so that any program running as this
/// user can read them without a prompt. A Keychain item normally trusts only
/// the exact signed program that created it, and without a paid Developer ID
/// every rebuild of these apps (ad-hoc signed) is a different program — so a
/// default item asked for approval again after every single build. The items
/// are still encrypted in the login keychain and unavailable while the Mac is
/// locked; what's given up is the per-app check. Items created by older
/// builds carry the old restrictive access list, so they're rewritten the
/// first time they're read (that read is the one last prompt).
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
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        if !hasOpenAccess(account: account) {
            replaceWithOpenAccess(value, account: account)
        }
        return value
    }

    static func write(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess, hasOpenAccess(account: account) {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        } else {
            replaceWithOpenAccess(value, account: account)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: openAccessFlag(account))
    }

    // MARK: - Open access

    /// Remembered per account (and so across rebuilds, which keep the same
    /// bundle ID and defaults domain) once an item has been stored with the
    /// open access list.
    private static func openAccessFlag(_ account: String) -> String { "keychainOpenAccess.\(account)" }

    private static func hasOpenAccess(account: String) -> Bool {
        UserDefaults.standard.bool(forKey: openAccessFlag(account))
    }

    /// Deletes any existing item and stores `value` fresh with the open
    /// access list. If the open-access add fails for any reason, falls back
    /// to a plain add so the secret is never lost.
    private static func replaceWithOpenAccess(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var addQuery = base
        addQuery[kSecValueData as String] = Data(value.utf8)
        if let access = openAccess(label: "\(service) \(account)") {
            addQuery[kSecAttrAccess as String] = access
            if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
                UserDefaults.standard.set(true, forKey: openAccessFlag(account))
                return
            }
            addQuery[kSecAttrAccess as String] = nil
        }
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// An access list whose "decrypt" entry has no application restriction.
    /// The SecAccess family is deprecated but is still how the login
    /// keychain's per-item trust list is expressed.
    private static func openAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, nil, &access) == errSecSuccess, let access else { return nil }
        guard let acls = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL], !acls.isEmpty else { return nil }
        for acl in acls {
            // A nil application list means "any application".
            guard SecACLSetContents(acl, nil, label as CFString, SecKeychainPromptSelector(rawValue: 0)) == errSecSuccess else { return nil }
        }
        return access
    }
}
