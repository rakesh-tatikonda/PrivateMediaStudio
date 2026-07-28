import Foundation
import AVFoundation
import UIKit

/// Generates a poster frame for a MediaItem and caches it to disk under
/// Application Support/Thumbnails, storing only the relative filename on the
/// model (`MediaItem.thumbnailRelativePath`) — never raw image bytes in
/// SwiftData, keeping the store small per the spec's "robust relational
/// mapping" intent.
enum ThumbnailGenerator {

    static func thumbnailsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func existingThumbnail(for item: MediaItem) -> UIImage? {
        guard let relativePath = item.thumbnailRelativePath else { return nil }
        let url = thumbnailsDirectory().appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    /// Local files: real frame grab via AVAssetImageGenerator at ~10% into the
    /// video (avoids black leader frames common at t=0).
    /// Network (SMB/FTP) items: generating a frame would mean opening a
    /// network stream just to grab a thumbnail, which is slow and often
    /// unreliable over LAN — falls back to a themed placeholder instead,
    /// per spec ("fallback for SMB/FTP").
    static func generateAndCache(for item: MediaItem) async -> String? {
        switch item.sourceType {
        case .localFile:
            guard let scoped = AccessScopedURL(mediaItem: item) else { return nil }
            defer { scoped.release() }
            return await generateLocalThumbnail(url: scoped.url, itemID: item.id)

        case .remoteURL, .smb, .ftp:
            // No network probing here by design — see doc comment above.
            return nil
        }
    }

    private static func generateLocalThumbnail(url: URL, itemID: UUID) async -> String? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        guard let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0 else {
            return nil
        }
        let targetTime = CMTime(seconds: duration.seconds * 0.1, preferredTimescale: 600)

        do {
            let cgImage = try await generator.image(at: targetTime).image
            let image = UIImage(cgImage: cgImage)
            guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }

            let filename = "\(itemID.uuidString).jpg"
            let destination = thumbnailsDirectory().appendingPathComponent(filename)
            try data.write(to: destination)
            return filename
        } catch {
            return nil
        }
    }
}
