import Foundation
import UIKit
import AVFoundation

/// Captures microphone audio and periodically runs it through WhisperEngine so
/// the transcript grows while the user is still talking. Runs in the
/// background via the `audio` UIBackgroundMode (declared in Info.plist) plus
/// an active AVAudioSession category of .playAndRecord.
@MainActor
final class LiveMicRecorder: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var rollingBuffer: [Float] = []
    private var elapsedBeforeCurrentChunk: TimeInterval = 0
    private var transcriptionTask: Task<Void, Never>?

    /// How much audio to accumulate before running inference on it. Shorter =
    /// lower latency but more model invocations (battery/CPU cost); whisper's
    /// own real-time examples use a similar window.
    private let chunkDuration: TimeInterval = 5.0
    private let sampleRate: Double = 16_000

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }

    @objc private func handleDidEnterBackground() {
        guard isRecording else { return }
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.backgroundLiveMic) else {
            stop()
            return
        }
        // Background Live Mic is enabled: UIBackgroundModes "audio" (Info.plist)
        // keeps AVAudioEngine's tap running, so no further action needed here.
    }

    func start(translateToEnglish: Bool, language: CaptionLanguage) throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        // .allowBluetooth was renamed .allowBluetoothHFP; same raw value, and
        // the rename kept the original availability, so no #available needed.
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw WhisperEngineError.transcriptionFailed("Could not set up audio format converter")
        }

        rollingBuffer.removeAll()
        elapsedBeforeCurrentChunk = 0
        liveSegments.removeAll()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converted = Self.convert(buffer, using: converter, targetFormat: targetFormat) else { return }
            Task { @MainActor in
                self.rollingBuffer.append(contentsOf: converted)
                self.flushChunkIfReady(translateToEnglish: translateToEnglish, language: language)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false

        // Flush whatever's left in the buffer as a final chunk.
        if !rollingBuffer.isEmpty {
            let remaining = rollingBuffer
            rollingBuffer.removeAll()
            transcribeChunk(remaining, translateToEnglish: false, language: .auto)
        }
    }

    private func flushChunkIfReady(translateToEnglish: Bool, language: CaptionLanguage) {
        let samplesPerChunk = Int(chunkDuration * sampleRate)
        guard rollingBuffer.count >= samplesPerChunk else { return }

        let chunk = Array(rollingBuffer.prefix(samplesPerChunk))
        rollingBuffer.removeFirst(samplesPerChunk)
        transcribeChunk(chunk, translateToEnglish: translateToEnglish, language: language)
    }

    private func transcribeChunk(_ samples: [Float], translateToEnglish: Bool, language: CaptionLanguage) {
        let baseOffset = elapsedBeforeCurrentChunk
        elapsedBeforeCurrentChunk += Double(samples.count) / sampleRate

        transcriptionTask = Task {
            do {
                let segments = try await WhisperEngine.shared.transcribe(
                    samples: samples,
                    translateToEnglish: translateToEnglish,
                    language: language
                )
                let offsetSegments = segments.map { seg -> TranscriptSegment in
                    var s = seg
                    s.startTime += baseOffset
                    s.endTime += baseOffset
                    return s
                }
                await MainActor.run {
                    self.liveSegments.append(contentsOf: offsetSegments)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Live transcription chunk failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Float]? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }

        var suppliedInput = false
        var conversionError: NSError?

        // AVAudioConverterInputBlock is @Sendable, and AVAudioPCMBuffer is not
        // Sendable, hence the warning. It is safe here specifically because
        // the converter invokes the block synchronously, on this thread,
        // before convert(to:error:) returns — the buffer never outlives the
        // call or crosses a concurrency boundary. Narrowing the escape hatch
        // to this one binding is better than @preconcurrency on the whole
        // import, which would also hide genuine races elsewhere in the file.
        nonisolated(unsafe) let inputBuffer = buffer

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}
