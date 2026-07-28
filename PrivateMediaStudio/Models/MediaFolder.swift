import Foundation
import SwiftData

/// A user-created folder for organizing media (Streams tab, "Folders" view).
/// A MediaItem belongs to at most one folder (to-one), mirroring how a
/// filesystem folder works — unlike playlists, which are many-to-many.
@Model
final class MediaFolder {
    var id: UUID
    var name: String
    var dateCreated: Date
    var sortIndex: Int

    @Relationship(deleteRule: .nullify, inverse: \MediaItem.folder)
    var items: [MediaItem] = []

    init(name: String, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.dateCreated = .now
        self.sortIndex = sortIndex
    }
}
