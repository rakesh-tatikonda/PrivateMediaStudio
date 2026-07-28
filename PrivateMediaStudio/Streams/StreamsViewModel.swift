import Foundation
import SwiftData
import UIKit
import AVFoundation

enum StreamsSection: String, CaseIterable, Identifiable {
    case allMedia = "All Media", folders = "Folders", playlists = "Playlists"
    var id: String { rawValue }
}

enum LibraryDisplayMode: String {
    case list, grid
}

enum StreamsAddError: LocalizedError {
    case invalidURL
    case notAVideoOrAudioFile
    case missingServerConnection
    case duplicateSubtitle

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid media URL."
        case .notAVideoOrAudioFile: return "That file doesn't look like a supported video or audio format."
        case .missingServerConnection: return "Pick a saved server connection first."
        case .duplicateSubtitle: return "This subtitle is already attached."
        }
    }
}

@MainActor
final class StreamsViewModel: ObservableObject {
    @Published var section: StreamsSection = .allMedia
    @Published var displayMode: LibraryDisplayMode = .grid
    @Published var errorMessage: String?
    @Published var isBusy = false

    // MARK: - Add via URL (incl. direct .m3u8 HLS)

    func addMediaViaURL(_ urlString: String, modelContext: ModelContext) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            errorMessage = StreamsAddError.invalidURL.localizedDescription
            return
        }

        let title = url.lastPathComponent.isEmpty ? url.host ?? "Stream" : url.lastPathComponent
        let item = MediaItem(title: title, sourceType: .remoteURL, remoteURLString: url.absoluteString)
        modelContext.insert(item)
        try? modelContext.save()
        // No thumbnail probing over the network at add-time — see ThumbnailGenerator's
        // doc comment. The player fills in duration once it actually opens the stream.
    }

    // MARK: - Add local video (security-scoped bookmark)

    @discardableResult
    func addLocalVideo(pickedURL: URL, modelContext: ModelContext) -> MediaItem? {
        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? pickedURL.bookmarkData(options: .minimalBookmark) else {
            errorMessage = StreamsAddError.notAVideoOrAudioFile.localizedDescription
            return nil
        }

        let item = MediaItem(
            title: pickedURL.deletingPathExtension().lastPathComponent,
            sourceType: .localFile,
            securityScopedBookmark: bookmark
        )
        modelContext.insert(item)
        try? modelContext.save()

        Task {
            isBusy = true
            defer { isBusy = false }
            if let filename = await ThumbnailGenerator.generateAndCache(for: item) {
                item.thumbnailRelativePath = filename
                try? modelContext.save()
            }
            if let duration = try? await AVURLAssetDurationProbe.duration(for: item) {
                item.durationSeconds = duration
                try? modelContext.save()
            }
        }

        return item
    }

    // MARK: - Attach local subtitle at creation time

    func attachSubtitle(pickedURL: URL, to item: MediaItem, modelContext: ModelContext) {
        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? pickedURL.bookmarkData(options: .minimalBookmark) else { return }

        guard !item.subtitleTracks.contains(where: { $0.displayName == pickedURL.lastPathComponent }) else {
            errorMessage = StreamsAddError.duplicateSubtitle.localizedDescription
            return
        }

        let track = SubtitleTrack(displayName: pickedURL.lastPathComponent, securityScopedBookmark: bookmark)
        track.mediaItem = item
        modelContext.insert(track)
        item.subtitleTracks.append(track)
        if item.defaultSubtitleTrackID == nil {
            item.defaultSubtitleTrackID = track.id
        }
        try? modelContext.save()
    }

    // MARK: - Connect to server (SMB/FTP) — saves the connection + one direct file

    func saveServerConnection(
        name: String, host: String, port: Int, protocolType: ServerProtocolType,
        sharePath: String?, username: String, password: String, modelContext: ModelContext
    ) -> ServerConnection? {
        let connection = ServerConnection(
            displayName: name, host: host, port: port, protocolType: protocolType,
            sharePath: sharePath, savedUsername: username
        )
        do {
            try KeychainManager.setPassword(password, forAccount: connection.keychainAccountKey)
        } catch {
            errorMessage = "Couldn't save credentials to Keychain: \(error.localizedDescription)"
            return nil
        }
        modelContext.insert(connection)
        try? modelContext.save()
        return connection
    }

    /// Adds a specific file path on an already-saved server as a MediaItem.
    /// (Full remote directory browsing would need a dedicated SMB/FTP client
    /// library beyond VLCKit's playback-only protocol support — out of scope
    /// here; VLCKit plays a fully-qualified smb://.../file.mkv URL directly,
    /// so pointing at one specific file works today without that dependency.)
    func addFileFromServer(_ connection: ServerConnection, filePath: String, title: String, modelContext: ModelContext) {
        let item = MediaItem(
            title: title,
            sourceType: connection.protocolType == .smb ? .smb : .ftp,
            serverConnectionID: connection.id
        )
        // Store the per-file path by reusing remoteURLString as a relative
        // path under the connection's share; ServerConnection.mediaURL()
        // builds the host/credentials part, PlayerViewModel appends this.
        item.remoteURLString = filePath
        modelContext.insert(item)
        try? modelContext.save()
    }

    // MARK: - Folders & Playlists

    func createFolder(name: String, modelContext: ModelContext) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        modelContext.insert(MediaFolder(name: name))
        try? modelContext.save()
    }

    func createPlaylist(name: String, modelContext: ModelContext) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        modelContext.insert(Playlist(name: name))
        try? modelContext.save()
    }

    func delete(_ item: MediaItem, modelContext: ModelContext) {
        // Clean up the cached poster thumbnail — without this, deleting media
        // from the library left its thumbnail image orphaned on disk
        // indefinitely, which is exactly the kind of leftover a
        // privacy-first, zero-retention app shouldn't have.
        if let relativePath = item.thumbnailRelativePath {
            let url = ThumbnailGenerator.thumbnailsDirectory().appendingPathComponent(relativePath)
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Deletes a saved SMB/FTP server connection *and* its Keychain-stored
    /// password. Before this existed, there was no way to remove a saved
    /// server at all — its credential would sit in Keychain permanently with
    /// no user-facing path to purge it, however unused it might sit there.
    /// Keychain cleanup runs even if the SwiftData delete is the part that
    /// matters most to get right, since a lingering DB row pointing at a
    /// dead Keychain entry is far less concerning than the reverse.
    func deleteServerConnection(_ connection: ServerConnection, modelContext: ModelContext) {
        try? KeychainManager.deletePassword(forAccount: connection.keychainAccountKey)
        modelContext.delete(connection)
        try? modelContext.save()
    }
}

/// Best-effort duration probe for local/HTTP(S) sources via AVFoundation.
/// SMB/FTP items are intentionally not probed this way (AVFoundation doesn't
/// speak those protocols) — their duration gets filled in by PlayerViewModel
/// once VLC actually opens the stream and reports it.
enum AVURLAssetDurationProbe {
    static func duration(for item: MediaItem) async throws -> Double? {
        guard item.sourceType == .localFile, let scoped = AccessScopedURL(mediaItem: item) else { return nil }
        defer { scoped.release() }
        let asset = AVURLAsset(url: scoped.url)
        let duration = try await asset.load(.duration)
        return duration.isValid ? duration.seconds : nil
    }
}
