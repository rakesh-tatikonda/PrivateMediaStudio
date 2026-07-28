import SwiftUI
import SwiftData

@main
struct PrivateMediaStudioApp: App {

    /// Single source of truth for the SwiftData store. All media metadata,
    /// folders, playlists, and subtitle references live here, on-device only —
    /// no CloudKit mirroring is configured, by design (privacy requirement).
    let modelContainer: ModelContainer = {
        let schema = Schema([
            MediaItem.self,
            MediaFolder.self,
            Playlist.self,
            PlaylistEntry.self,
            SubtitleTrack.self,
            ServerConnection.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            Self.applyDataProtection(to: configuration.url)
            return container
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    /// Explicitly sets file-level data protection on the SwiftData store
    /// (and its -wal/-shm journal sidecars) rather than relying on whatever
    /// the platform default happens to resolve to. This library holds media
    /// metadata, SMB/FTP server hostnames/usernames (not passwords — those
    /// are Keychain-only), and subtitle sync settings, so it's worth
    /// protecting even though it's less sensitive than the Keychain data.
    /// `.completeUntilFirstUserAuthentication` (not `.complete`) is the
    /// deliberate choice: encrypted at rest before first unlock after boot,
    /// but still readable while the device is locked *after* that — which
    /// this app's own Background Translations / Background Live Mic
    /// settings depend on.
    private static func applyDataProtection(to storeURL: URL) {
        let fileManager = FileManager.default
        for path in [storeURL.path, storeURL.path + "-wal", storeURL.path + "-shm"] {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
        }
    }

    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.preferredColorScheme)
        }
        .modelContainer(modelContainer)
    }
}
