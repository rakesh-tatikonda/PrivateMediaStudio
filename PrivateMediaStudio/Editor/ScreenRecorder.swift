import Foundation
import ReplayKit
import AVFoundation
import Photos
import UIKit
import VideoToolbox

enum ScreenRecorderError: LocalizedError {
    case notAvailable
    case alreadyRecording
    case writerSetupFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Screen recording isn't available on this device right now."
        case .alreadyRecording: return "Already recording."
        case .writerSetupFailed(let reason): return "Couldn't start the recorder: \(reason)"
        case .saveFailed(let reason): return "Couldn't save the recording: \(reason)"
        }
    }
}

/// Captures the screen (+ mic/app audio) via ReplayKit and writes it straight
/// to an HEVC (H.265) .mp4 using AVAssetWriter, per the spec's "Highly
/// Compressed Screen Recorder" requirement — HEVC gives a meaningfully
/// smaller file than H.264 at the same quality, at the cost of needing an
/// A9+ device (iPhone 6s / 2015 or later — a non-issue in practice today).
@MainActor
final class ScreenRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var appAudioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var startTime: CMTime?
    private var outputURL: URL?
    private var timer: Timer?

    func startRecording() {
        guard !isRecording else { return }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            errorMessage = ScreenRecorderError.notAvailable.localizedDescription
            return
        }

        recorder.isMicrophoneEnabled = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenRecording-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mp4")
        outputURL = url
        try? FileManager.default.removeItem(at: url)

        do {
            try setUpWriter(outputURL: url)
        } catch {
            errorMessage = ScreenRecorderError.writerSetupFailed(error.localizedDescription).localizedDescription
            return
        }

        sessionStarted = false
        startTime = nil

        recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
                return
            }
            Task { @MainActor in
                self.process(sampleBuffer: sampleBuffer, type: bufferType)
            }
        } completionHandler: { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.isRecording = true
                    self?.startElapsedTimer()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = false
                self.timer?.invalidate()
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                await self.finishWritingAndSave()
            }
        }
    }

    // MARK: - AVAssetWriter pipeline

    private func setUpWriter(outputURL: URL) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let screenBounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(screenBounds.width * scale),
            AVVideoHeightKey: Int(screenBounds.height * scale),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
        let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micInput.expectsMediaDataInRealTime = true
        let appInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        appInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(vInput), writer.canAdd(micInput), writer.canAdd(appInput) else {
            throw ScreenRecorderError.writerSetupFailed("Writer rejected one or more inputs")
        }
        writer.add(vInput)
        writer.add(micInput)
        writer.add(appInput)

        self.assetWriter = writer
        self.videoInput = vInput
        self.micAudioInput = micInput
        self.appAudioInput = appInput
    }

    private func process(sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard let writer = assetWriter, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if !sessionStarted {
            guard type == .video else { return } // wait for the first video frame to anchor the session
            writer.startWriting()
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            startTime = pts
            sessionStarted = true
        }

        switch type {
        case .video:
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audioMic:
            if let micAudioInput, micAudioInput.isReadyForMoreMediaData {
                micAudioInput.append(sampleBuffer)
            }
        case .audioApp:
            if let appAudioInput, appAudioInput.isReadyForMoreMediaData {
                appAudioInput.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }

    private func finishWritingAndSave() async {
        guard let writer = assetWriter, let outputURL else { return }
        videoInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        appAudioInput?.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            errorMessage = ScreenRecorderError.saveFailed(writer.error?.localizedDescription ?? "Unknown writer error").localizedDescription
            return
        }

        do {
            try await saveToPhotos(outputURL)
            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            errorMessage = error.localizedDescription
        }

        assetWriter = nil
        videoInput = nil
        micAudioInput = nil
        appAudioInput = nil
        self.outputURL = nil
        elapsedSeconds = 0
    }

    private func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ScreenRecorderError.saveFailed("Photos permission denied")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ScreenRecorderError.saveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }

    private func startElapsedTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }
}
