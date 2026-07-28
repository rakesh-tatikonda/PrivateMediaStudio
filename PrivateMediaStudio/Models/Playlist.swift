import Foundation
import SwiftData

/// A user-created, ordered playlist (Streams tab, "Playlists" view). A single
/// MediaItem can belong to multiple playlists (many-to-many) — spec requires
/// this explicitly. Order within a playlist is tracked via `entries`
/// (a join model with a sortIndex) rather than relying on array order, since
/// SwiftData relationship arrays don't guarantee stable custom ordering.
@Model
final class Playlist {
    var id: UUID
    var name: String
    var dateCreated: Date

    var items: [MediaItem] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateCreated = .now
    }

    /// Items in playback order, for handing to VLCMediaListPlayer.
    var orderedItems: [MediaItem] {
        entries.sorted { $0.sortIndex < $1.sortIndex }.compactMap { $0.mediaItem }
    }

    func append(_ item: MediaItem) {
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
        }
        let nextIndex = (entries.map(\.sortIndex).max() ?? -1) + 1
        entries.append(PlaylistEntry(mediaItem: item, playlist: self, sortIndex: nextIndex))
    }
}

/// Join entity carrying explicit ordering for a Playlist <-> MediaItem pair.
@Model
final class PlaylistEntry {
    var id: UUID
    var sortIndex: Int
    var mediaItem: MediaItem?
    var playlist: Playlist?

    init(mediaItem: MediaItem, playlist: Playlist, sortIndex: Int) {
        self.id = UUID()
        self.mediaItem = mediaItem
        self.playlist = playlist
        self.sortIndex = sortIndex
    }
}
