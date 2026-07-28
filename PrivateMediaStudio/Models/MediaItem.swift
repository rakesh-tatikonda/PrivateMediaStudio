import Foundation
import SwiftData

enum MediaSourceType: String, Codable {
    case localFile
    case remoteURL      // direct URL, incl. HLS .m3u8
    case smb
    case ftp
}

/// A single piece of media in the library (Streams tab). Stores everything
/// needed to relocate the file (security-scoped bookmark for local files,
/// or connection info for network sources), resume playback exactly where the
/// user left off, and show progress bars in list/grid view.
@Model
final class MediaItem {
    var id: UUID
    var title: String
    var sourceType: MediaSourceType
    var dateAdded: Date

    /// For .localFile: a security-scoped bookmark so the app can re-access the
    /// file across launches without re-prompting the user via a file picker.
    @Attribute(.externalStorage) var securityScopedBookmark: Data?

    /// For .remoteURL / .smb / .ftp
    var remoteURLString: String?
    /// Foreign-key-style link to a stored server connection (SMB/FTP), if any.
    /// Credentials themselves live in Keychain — never here.
    var serverConnectionID: UUID?

    /// Cached poster frame, stored as a relative path under the app's
    /// Application Support thumbnails directory (not raw image data, to keep
    /// the SwiftData store small).
    var thumbnailRelativePath: String?

    var durationSeconds: Double?

    /// Resume playback support — updated continuously during playback.
    var lastPlaybackPositionSeconds: Double = 0
    var watchedFraction: Double = 0 // 0...1, drives the progress bar overlay

    // Relationships
    var folder: MediaFolder?

    @Relationship(deleteRule: .nullify, inverse: \Playlist.items)
    var playlists: [Playlist] = []

    @Relationship(deleteRule: .cascade, inverse: \SubtitleTrack.mediaItem)
    var subtitleTracks: [SubtitleTrack] = []

    /// Which attached subtitle track should auto-load when this item opens.
    var defaultSubtitleTrackID: UUID?

    init(
        title: String,
        sourceType: MediaSourceType,
        securityScopedBookmark: Data? = nil,
        remoteURLString: String? = nil,
        serverConnectionID: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.sourceType = sourceType
        self.dateAdded = .now
        self.securityScopedBookmark = securityScopedBookmark
        self.remoteURLString = remoteURLString
        self.serverConnectionID = serverConnectionID
    }

    /// Resolves the local file URL from the stored bookmark, re-establishing
    /// the security scope. Call `stopAccessingSecurityScopedResource()` on the
    /// returned URL when done (mirrored by `AccessScopedURL` helper below).
    func resolveLocalURL() -> URL? {
        guard let bookmark = securityScopedBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url
    }
}

/// RAII-style wrapper so callers can't forget to stop accessing a
/// security-scoped resource.
struct AccessScopedURL {
    let url: URL
    private let didStartAccessing: Bool

    init?(mediaItem: MediaItem) {
        guard let url = mediaItem.resolveLocalURL() else { return nil }
        self.url = url
        self.didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    func release() {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
