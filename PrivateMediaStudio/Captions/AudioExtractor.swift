import Foundation
import AVFoundation

enum AudioExtractionError: Error {
    case noAudioTrack
    case exportFailed(String)
    case exportCancelled
}

/// Pipeline step 1: "extract audio (if video) via AVAssetExportSession to
/// temporaryDirectory". Produces an .m4a in `FileManager.default.temporaryDirectory`
/// that the caller (WhisperEngine) reads, and that CaptionsViewModel deletes
/// once transcription finishes (auto-cleanup requirement).
enum AudioExtractor {

    /// Returns the URL to a freshly-created temporary .m4a containing just the
    /// audio track of `sourceURL`. If `sourceURL` is already audio-only, the
    /// export still runs (cheap) so downstream code always deals with one
    /// consistent container/codec.
    static func extractAudio(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw AudioExtractionError.noAudioTrack }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.exportFailed("Could not create export session")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw AudioExtractionError.exportCancelled
        default:
            throw AudioExtractionError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown export error")
        }
    }

    /// Best-effort cleanup of a temp file produced above (and of the
    /// downloaded-from-URL temp copy, for Media URL input). Never throws —
    /// called from `defer` blocks.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
