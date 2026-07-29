import Foundation
import SwiftWhisper

enum WhisperEngineError: LocalizedError {
    case modelNotBundled(String)
    case transcriptionFailed(String)

    // Without LocalizedError, Swift bridges these to NSError and surfaces only
    // "(WhisperEngineError error 1.)" — the associated value, which is the
    // only part that identifies what actually went wrong, is discarded.
    var errorDescription: String? {
        switch self {
        case .modelNotBundled(let name):
            return "The speech model \(name) is missing from the app bundle."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
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
    private func ensureModelLoaded(modelName: String, translateToEnglish: Bool, language: CaptionLanguage) throws -> Whisper {
        if let whisper, loadedModelName == modelName {
            whisper.params.translate = translateToEnglish
            if let lang = language.whisperParamValue { whisper.params.language = lang }
            return whisper
        }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: nil, subdirectory: "Models")
            ?? Bundle.main.url(forResource: (modelName as NSString).deletingPathExtension,
                                withExtension: (modelName as NSString).pathExtension) else {
            throw WhisperEngineError.modelNotBundled(modelName)
        }

        let params = WhisperParams.default
        params.translate = translateToEnglish
        if let lang = language.whisperParamValue { params.language = lang }
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
        language: CaptionLanguage = .auto,
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
        } catch let error as WhisperError {
            // SwiftWhisper's own error type, which is the informative one.
            throw WhisperEngineError.transcriptionFailed(String(describing: error))
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
    func whisper(_ whisper: Whisper, didProcessNewSegments segments: [Segment], atIndex index: Int) {}
    func whisper(_ whisper: Whisper, didCompleteWithSegments segments: [Segment]) {}
    func whisper(_ whisper: Whisper, didErrorWith error: Error) {}
}

enum CaptionLanguage: String, CaseIterable, Identifiable {
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

    /// whisper.cpp / ISO 639-1 codes. Kept as strings deliberately: this maps
    /// onto SwiftWhisper's own `WhisperLanguage`, and going through
    /// `init(rawValue:)` means we depend only on the documented language codes
    /// rather than on that enum's Swift case spellings.
    var isoCode: String {
        switch self {
        case .auto: return "auto"
        case .english: return "en"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .japanese: return "ja"
        case .mandarin: return "zh"
        case .korean: return "ko"
        case .portuguese: return "pt"
        case .italian: return "it"
        case .russian: return "ru"
        case .arabic: return "ar"
        case .hindi: return "hi"
        }
    }

    /// nil when the code is not one SwiftWhisper recognises — callers then
    /// leave `WhisperParams.default`'s language untouched.
    var whisperParamValue: SwiftWhisper.WhisperLanguage? {
        SwiftWhisper.WhisperLanguage(rawValue: isoCode)
    }
}
