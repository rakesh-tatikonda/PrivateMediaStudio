import Foundation
import Photos
import ffmpegkit

enum FFmpegExportError: LocalizedError {
    case ffmpegFailed(String)
    case photosSaveFailed(String)
    case photosPermissionDenied

    var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let log): return "Export failed: \(log)"
        case .photosSaveFailed(let reason): return "Couldn't save to Photos: \(reason)"
        case .photosPermissionDenied: return "Photos access is required to save the exported video."
        }
    }
}

@MainActor
final class FFmpegExporter: ObservableObject {
    @Published var progress: Double = 0 // 0...1
    @Published var isExporting = false
    @Published var statusMessage: String?

    private var currentSession: FFmpegSession?

    /// Runs the full export → temp .mp4 → save to Photos pipeline.
    func export(project: EditorProject, subtitleCues: [SubtitleCue]) async -> Result<Void, Error> {
        isExporting = true
        progress = 0
        statusMessage = "Preparing\u{2026}"
        defer { isExporting = false }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mp4")

        var assURL: URL?
        if !subtitleCues.isEmpty {
            let (w, h) = project.resolution.dimensions
            assURL = SRTToASSConverter.write(cues: subtitleCues, overlay: project.subtitleOverlay, videoWidth: w, videoHeight: h)
        }

        let args = FFmpegCommandBuilder.buildExportArguments(project: project, outputURL: outputURL, assSubtitlePath: assURL)
        let totalDurationMs = project.totalVideoDuration * 1000

        statusMessage = "Encoding\u{2026}"
        let ffmpegResult: Result<Void, Error> = await withCheckedContinuation { continuation in
            let session = FFmpegKit.executeAsync(
                withArguments: args,
                withCompleteCallback: { [weak self] session in
                    Task { @MainActor in
                        if let assURL { try? FileManager.default.removeItem(at: assURL) }
                        guard let self else { return }
                        let returnCode = session?.getReturnCode()
                        if let returnCode, ReturnCode.isSuccess(returnCode) {
                            continuation.resume(returning: .success(()))
                        } else {
                            let log = session?.getFailStackTrace() ?? session?.getAllLogsAsString() ?? "Unknown FFmpeg error"
                            continuation.resume(returning: .failure(FFmpegExportError.ffmpegFailed(log)))
                        }
                        self.currentSession = nil
                    }
                },
                withLogCallback: nil,
                withStatisticsCallback: { [weak self] statistics in
                    guard totalDurationMs > 0, let statistics else { return }
                    let processedMs = Double(statistics.getTime())
                    Task { @MainActor in
                        self?.progress = min(max(processedMs / totalDurationMs, 0), 1)
                    }
                }
            )
            self.currentSession = session
        }

        guard case .success = ffmpegResult else {
            return ffmpegResult
        }

        statusMessage = "Saving to Photos\u{2026}"
        do {
            try await saveToPhotos(outputURL)
            try? FileManager.default.removeItem(at: outputURL)
            statusMessage = "Done"
            return .success(())
        } catch {
            statusMessage = "Export finished but saving to Photos failed"
            return .failure(error)
        }
    }

    /// Cancels the in-flight FFmpeg session, if any.
    /// (Broad `FFmpegKit.cancel()` rather than a per-session cancel — this
    /// app only ever runs one export at a time, so cancelling "everything
    /// FFmpeg is doing" and cancelling "this export" are equivalent here.)
    func cancel() {
        FFmpegKit.cancel()
        currentSession = nil
        isExporting = false
        statusMessage = "Cancelled"
    }

    private func saveToPhotos(_ videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw FFmpegExportError.photosPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FFmpegExportError.photosSaveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }
}
