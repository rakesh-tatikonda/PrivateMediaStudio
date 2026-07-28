import Foundation
import SwiftData

enum ServerProtocolType: String, Codable, CaseIterable, Identifiable {
    case smb, ftp
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var defaultPort: Int { self == .smb ? 445 : 21 }
}

/// A saved SMB/FTP server (Streams tab, "Connect to Server"). Only
/// non-sensitive connection info lives here; username/password are stored in
/// Keychain under `keychainAccountKey` via KeychainManager, and this model
/// only carries the opaque key that unlocks them.
@Model
final class ServerConnection {
    var id: UUID
    var displayName: String
    var host: String
    var port: Int
    var protocolType: ServerProtocolType
    var sharePath: String?          // e.g. SMB share name
    var savedUsername: String       // ok to store — not secret; password is what's protected
    var keychainAccountKey: String  // key into KeychainManager for the password
    var dateAdded: Date

    init(displayName: String, host: String, port: Int, protocolType: ServerProtocolType, sharePath: String? = nil, savedUsername: String) {
        // @Model rewrites stored properties into computed accessors backed by
        // SwiftData storage, so `self.id` cannot be read until every property
        // is initialised — even though it was assigned first. Hold the value
        // locally and use that instead.
        let newID = UUID()
        self.id = newID
        self.displayName = displayName
        self.host = host
        self.port = port
        self.protocolType = protocolType
        self.sharePath = sharePath
        self.savedUsername = savedUsername
        self.keychainAccountKey = "server-\(newID.uuidString)"
        self.dateAdded = .now
    }

    /// Builds the URL VLCKit expects for this connection, e.g.
    /// smb://user:pass@host/share or ftp://user:pass@host/path.
    /// Password is fetched from Keychain at the moment of use, never cached
    /// on this model in memory beyond the call site.
    func mediaURL() throws -> URL {
        let password = try KeychainManager.password(forAccount: keychainAccountKey)
        var components = URLComponents()
        components.scheme = protocolType.rawValue
        components.host = host
        components.port = port
        components.user = savedUsername
        components.password = password
        components.path = sharePath.map { $0.hasPrefix("/") ? $0 : "/\($0)" } ?? ""
        guard let url = components.url else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }
        return url
    }
}
