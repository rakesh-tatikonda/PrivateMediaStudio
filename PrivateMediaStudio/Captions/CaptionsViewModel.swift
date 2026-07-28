import Foundation
import UIKit
import AVFoundation

enum CaptionsInputMode: String, CaseIterable, Identifiable {
    case file = "Local Audio/Video"
    case liveMic = "Live Mic"
    case url = "Media URL"
    var id: String { rawValue }
}

enum CaptionsPipelineError: LocalizedError {
    case downloadFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): return "Couldn't download media: \(reason)"
        case .invalidURL: return "That doesn't look like a valid media URL."
        }
    }
}

@MainActor
final class CaptionsViewModel: ObservableObject {

    @Published var inputMode: CaptionsInputMode = .file
    @Published var translateToEnglish = false
    @Published var selectedLanguage: CaptionLanguage = .auto
    @Published var mediaURLText = ""

    @Published private(set) var isProcessing = false
    @Published private(set) var progress: Float = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published var errorMessage: String?

    @Published private(set) var lastProcessedAudioURL: URL?

    let liveMicRecorder = LiveMicRecorder()

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Local file / picked video or audio

    func processLocalFile(at pickedURL: URL) {
        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        beginBackgroundTask()

        Task {
            defer {
                if didAccess { pickedURL.stopAccessingSecurityScopedResource() }
                endBackgroundTask()
            }
            await runPipeline(sourceURL: pickedURL, isTemporaryCopy: false)
        }
    }

    // MARK: - Media URL

    func processMediaURL() {
        guard let url = URL(string: mediaURLText),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            errorMessage = CaptionsPipelineError.invalidURL.localizedDescription
            return
        }

        beginBackgroundTask()
        isProcessing = true
        progress = 0
        errorMessage = nil

        Task {
            defer { endBackgroundTask() }
            do {
                let (localURL, _) = try await URLSession.shared.download(from: url)
                // Give the downloaded temp file a proper extension so
                // AVAssetExportSession can infer its container correctly.
                let renamed = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
                try FileManager.default.moveItem(at: localURL, to: renamed)

                await runPipeline(sourceURL: renamed, isTemporaryCopy: true)
            } catch {
                isProcessing = false
                errorMessage = CaptionsPipelineError.downloadFailed(error.localizedDescription).localizedDescription
            }
        }
    }

    // MARK: - Live mic

    func startLiveMic() {
        do {
            try liveMicRecorder.start(translateToEnglish: translateToEnglish, language: selectedLanguage)
        } catch {
            errorMessage = "Couldn't start microphone: \(error.localizedDescription)"
        }
    }

    func stopLiveMic() {
        liveMicRecorder.stop()
        segments = liveMicRecorder.liveSegments
    }

    // MARK: - Shared pipeline: extract audio (if needed) -> whisper -> cleanup

    private func runPipeline(sourceURL: URL, isTemporaryCopy: Bool) async {
        isProcessing = true
        progress = 0
        errorMessage = nil
        segments = []

        var extractedAudioURL: URL?
        defer {
            if let extractedAudioURL {
                AudioExtractor.cleanup(extractedAudioURL)
            }
            if isTemporaryCopy {
                AudioExtractor.cleanup(sourceURL)
            }
            isProcessing = false
        }

        do {
            let audioURL = try await AudioExtractor.extractAudio(from: sourceURL)
            extractedAudioURL = audioURL
            lastProcessedAudioURL = audioURL // used by "Export .m4a" — copied out before cleanup runs

            let samples = try PCMAudioLoader.loadMono16kFloatSamples(from: audioURL)

            let result = try await WhisperEngine.shared.transcribe(
                samples: samples,
                translateToEnglish: translateToEnglish,
                language: selectedLanguage,
                progress: { [weak self] p in
                    Task { @MainActor in self?.progress = p }
                }
            )
            segments = result
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportTXT() -> URL? { TranscriptExporter.exportPlainText(segments) }
    func exportSRT() -> URL? { TranscriptExporter.exportSRT(segments) }
    func exportM4A() -> URL? {
        guard let source = lastProcessedAudioURL else { return nil }
        return TranscriptExporter.exportAudio(from: source)
    }

    // MARK: - Background task (file/URL modes finish processing when minimized)

    private func beginBackgroundTask() {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.backgroundTranslations) else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TranscriptionPipeline") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
