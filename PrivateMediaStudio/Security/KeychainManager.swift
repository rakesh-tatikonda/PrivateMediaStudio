import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case notFound
}

/// Thin wrapper over the Security framework's Keychain Services API.
/// Server credentials (SMB/FTP usernames + passwords) are stored here, keyed
/// by an opaque UUID account string that the corresponding SwiftData
/// `ServerConnection.keychainAccountKey` points to — the credential value
/// itself never touches SwiftData/disk in plaintext.
enum KeychainManager {

    /// Derived from the bundle ID rather than hardcoded, so the real
    /// identifier lives only in build configuration and never in source.
    private static let service =
        (Bundle.main.bundleIdentifier ?? "app") + ".servercredentials"

    /// Stores (or overwrites) the password for the given account key.
    static func setPassword(_ password: String, forAccount account: String) throws {
        guard let data = password.data(using: .utf8) else { throw KeychainError.encodingFailed }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try update first; if the item doesn't exist yet, add it.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // Never sync to iCloud Keychain and never include in device backups —
            // matches the app's zero-cloud-egress requirement.
            addQuery[kSecAttrSynchronizable as String] = false
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    static func password(forAccount account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return password
    }

    static func deletePassword(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
