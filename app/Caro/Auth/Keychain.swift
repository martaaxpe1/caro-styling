import Foundation
import Security

/// The iPhone's Keychain: an encrypted safe for small secrets, kept by iOS outside the app.
/// Caro keeps one thing in it, the session token, so you stay signed in after closing the app.
/// Apple's Security framework does the work; it is part of iOS, not an extra package.
enum Keychain {
    private static let service = "com.carostyling.app"
    private static let account = "session-token"

    /// What identifies Caro's token among everything in the Keychain.
    private static var tokenQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func saveToken(_ token: String) {
        deleteToken()
        var item = tokenQuery
        item[kSecValueData as String] = Data(token.utf8)
        // Readable once the iPhone has been unlocked after a restart, and never moved to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func readToken() -> String? {
        var query = tokenQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        SecItemDelete(tokenQuery as CFDictionary)
    }
}
