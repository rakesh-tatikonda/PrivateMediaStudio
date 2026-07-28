import Foundation
import SwiftWhisper

enum WhisperEngineError: Error {
    case modelNotBundled
    case transcriptionFailed(String)
}

/// Owns the whisper.cpp model instance and turns raw PCM samples into
/// `TranscriptSegment`s. One instance is reused across a session (loading the
/// ~140MB model is the expensive part) rather than re-created per file.
@MainActor
final class WhisperEngine {

    static let shared = WhisperEngine()

    private var whisper: Whisper?
    private var loadedModelName: String?

    /// Loads (or reuses) the bundled ggml model. Kept lazy since Live Mic mode
    /// and one-shot file transcription both go through this, and we don't want
    /// to pay the load cost until the user actually starts a transcription.
    private func ensureModelLoaded(modelName: String, translateToEnglish: Bool, language: WhisperLanguage) throws -> Whisper {
        if let whisper, loadedModelName == modelName {
            whisper.params.translate = translateToEnglish
            whisper.params.language = language.whisperParamValue
            return whisper
        }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: nil, subdirectory: "Models")
            ?? Bundle.main.url(forResource: (modelName as NSString).deletingPathExtension,
                                withExtension: (modelName as NSString).pathExtension) else {
            throw WhisperEngineError.modelNotBundled
        }

        var params = WhisperParams.default
        params.translate = translateToEnglish
        params.language = language.whisperParamValue
        params.print_progress = false
        params.print_realtime = false

        let instance = Whisper(fromFileURL: modelURL, withParams: params)
        self.whisper = instance
        self.loadedModelName = modelName
        return instance
    }

    /// Transcribes a full buffer of 16kHz mono Float32 samples (a whole file,
    /// or the Live Mic rolling window) and returns segments with real
    /// start/end timecodes for SRT export.
    func transcribe(
        samples: [Float],
        modelName: String = "ggml-base.en.bin",
        translateToEnglish: Bool,
        language: WhisperLanguage = .auto,
        progress: ((Float) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        let whisper = try ensureModelLoaded(modelName: modelName, translateToEnglish: translateToEnglish, language: language)

        if let progress {
            whisper.delegate = ProgressForwarder(onProgress: progress)
        }

        do {
            let rawSegments = try await whisper.transcribe(audioFrames: samples)
            return rawSegments.map {
                TranscriptSegment(
                    startTime: Double($0.startTime) / 1000.0,
                    endTime: Double($0.endTime) / 1000.0,
                    text: $0.text.trimmingCharacters(in: .whitespaces)
                )
            }
        } catch {
            throw WhisperEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Releases the loaded model, e.g. when the app is backgrounded for a long
    /// time or on a memory warning. Re-loaded transparently on next use.
    func unloadModel() {
        whisper = nil
        loadedModelName = nil
    }
}

/// Forwards SwiftWhisper's per-segment delegate callbacks into a simple
/// progress closure the view model can bind to a ProgressView.
private final class ProgressForwarder: WhisperDelegate {
    let onProgress: (Float) -> Void
    init(onProgress: @escaping (Float) -> Void) { self.onProgress = onProgress }

    func whisper(_ whisper: Whisper, didUpdateProgress progress: Double) {
        onProgress(Float(progress))
    }
    func whisper(_ whisper: Whisper, didProcessNewSegments segments: [WhisperSegment], atIndex index: Int) {}
    func whisper(_ whisper: Whisper, didCompleteWithSegments segments: [WhisperSegment]) {}
    func whisper(_ whisper: Whisper, didErrorWith error: Error) {}
}

enum WhisperLanguage: String, CaseIterable, Identifiable {
    case auto, english, spanish, french, german, japanese, mandarin, korean, portuguese, italian, russian, arabic, hindi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .mandarin: return "Mandarin"
        case .korean: return "Korean"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        }
    }

    /// whisper.cpp language codes.
    var whisperParamValue: WhisperParams.Language {
        switch self {
        case .auto: return .auto
        case .english: return .english
        case .spanish: return .spanish
        case .french: return .french
        case .german: return .german
        case .japanese: return .japanese
        case .mandarin: return .chinese
        case .korean: return .korean
        case .portuguese: return .portuguese
        case .italian: return .italian
        case .russian: return .russian
        case .arabic: return .arabic
        case .hindi: return .hindi
        }
    }
}
