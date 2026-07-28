import Foundation
import SwiftData

/// A subtitle file (.srt) attached to a MediaItem, stored as a security-scoped
/// bookmark so it survives app relaunches without re-prompting. Also carries
/// the per-track sync offset the player's sync menu (-600s..+600s slider)
/// writes to.
@Model
final class SubtitleTrack {
    var id: UUID
    var displayName: String
    var languageCode: String?

    @Attribute(.externalStorage) var securityScopedBookmark: Data

    /// Manual sync adjustment in seconds, applied at render time (player adds
    /// this to every cue's start/end time). Range enforced in UI: -600...600.
    var syncOffsetSeconds: Double = 0

    var mediaItem: MediaItem?

    init(displayName: String, securityScopedBookmark: Data, languageCode: String? = nil) {
        self.id = UUID()
        self.displayName = displayName
        self.securityScopedBookmark = securityScopedBookmark
        self.languageCode = languageCode
    }

    func resolveURL() -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: securityScopedBookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
