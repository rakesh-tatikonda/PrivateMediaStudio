import Foundation
import AVFoundation

enum PCMConversionError: Error {
    case converterCreationFailed
    case readFailed(String)
}

/// whisper.cpp's inference API expects raw 16kHz, mono, Float32 PCM samples.
/// Source files (m4a from AudioExtractor, or any user-picked audio file) are
/// almost never already in that format, so this does the resample/downmix.
enum PCMAudioLoader {

    static func loadMono16kFloatSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw PCMConversionError.converterCreationFailed
        }

        // Fast path: already in the target format.
        if file.processingFormat.sampleRate == 16_000,
           file.processingFormat.channelCount == 1 {
            return try readAllSamples(from: file)
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw PCMConversionError.converterCreationFailed
        }

        let sourceFrameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: sourceFrameCount) else {
            throw PCMConversionError.readFailed("Could not allocate source buffer")
        }
        try file.read(into: sourceBuffer)

        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(sourceFrameCount) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            throw PCMConversionError.readFailed("Could not allocate output buffer")
        }

        var error: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard status != .error else {
            throw PCMConversionError.readFailed(error?.localizedDescription ?? "Unknown conversion error")
        }

        guard let channelData = outputBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    private static func readAllSamples(from file: AVAudioFile) throws -> [Float] {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw PCMConversionError.readFailed("Could not allocate buffer")
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }
}
