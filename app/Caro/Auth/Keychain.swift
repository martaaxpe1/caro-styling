import Foundation
import Security

/// The iPhone's Keychain: an encrypted safe for small secrets, kept by iOS outside the app.
/// Caro keeps the session token in it, so you stay signed in after closing the app, and the
/// address of the server that token belongs to.
/// Apple's Security framework does the work; it is part of iOS, not an extra package.
///
/// T10: both are kept in a shared Keychain group (Keychain sharing), so Caro's share extension
/// can read them too and send an image to Get the look while the app is closed. Only apps and
/// extensions signed by the same Apple team can open that group. A token saved before T10 is
/// moved into the group the first time the app opens (`shareWithExtension`).
///
/// This file is part of both targets: the app and the share extension.
enum Keychain {
    private static let service = "com.carostyling.app"
    private static let tokenAccount = "session-token"
    private static let serverAccount = "server-url"

    /// "TEAMID.com.carostyling.shared", from Info.plist (CaroKeychainGroup), where Xcode fills in
    /// the team. Nil if it is missing; then the token stays the app's own.
    private static let sharedGroup: String? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "CaroKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$")
        else { return nil }
        return group
    }()

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // MARK: The session token

    /// Saves the token, and the server it came from (this app's server).
    static func saveToken(_ token: String) {
        save(token, account: tokenAccount)
        save(AppConfig.serverURL.absoluteString, account: serverAccount)
    }

    static func readToken() -> String? {
        read(tokenAccount)
    }

    static func deleteToken() {
        SecItemDelete(query(tokenAccount) as CFDictionary)
        SecItemDelete(query(serverAccount) as CFDictionary)
    }

    /// The server the saved token belongs to. The share extension sends to it, so in a build
    /// run from Xcode it reaches the Mac the app was using.
    static func readServer() -> URL? {
        read(serverAccount).flatMap(URL.init(string:))
    }

    /// When the app opens with a token: saves it again in the shared group, with this app's
    /// server, so the share extension can use them. Does nothing without a token.
    static func shareWithExtension() {
        guard let token = readToken() else { return }
        saveToken(token)
    }

    // MARK: Reading and writing

    private static func save(_ value: String, account: String) {
        // Without a group, this finds and deletes the item wherever it is: the app's own
        // group or the shared one.
        SecItemDelete(query(account) as CFDictionary)
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        // Readable once the iPhone has been unlocked after a restart, and never moved to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let sharedGroup {
            item[kSecAttrAccessGroup as String] = sharedGroup
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
            // The group is not allowed in this build (no Keychain sharing): keep it the app's own.
            item.removeValue(forKey: kSecAttrAccessGroup as String)
        }
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func read(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
