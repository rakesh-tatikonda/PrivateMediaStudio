import Foundation

enum TranscriptExporter {

    static func exportPlainText(_ segments: [TranscriptSegment]) -> URL? {
        let text = segments.map(\.text).joined(separator: "\n")
        return write(text, extension: "txt")
    }

    static func exportSRT(_ segments: [TranscriptSegment]) -> URL? {
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(srtTimestamp(segment.startTime)) --> \(srtTimestamp(segment.endTime))")
            lines.append(segment.text)
            lines.append("")
        }
        return write(lines.joined(separator: "\n"), extension: "srt")
    }

    /// Copies the already-extracted/recorded audio to a permanent, user-facing
    /// .m4a in Documents (the temp copy used during processing gets deleted).
    static func exportAudio(from sourceURL: URL) -> URL? {
        let destination = documentsDirectory()
            .appendingPathComponent("Transcript-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("m4a")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            protect(destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        let totalMillis = Int((time * 1000).rounded())
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let seconds = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func write(_ content: String, extension ext: String) -> URL? {
        let url = documentsDirectory()
            .appendingPathComponent("Transcript-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension(ext)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            protect(url)
            return url
        } catch {
            return nil
        }
    }

    /// Transcripts can capture sensitive spoken content (voice memos,
    /// private conversations, meeting audio, etc.), and these particular
    /// files live in Documents — reachable via the Files app / AirDrop
    /// since the project enables file sharing — so they get the same
    /// explicit at-rest protection as the SwiftData store rather than
    /// whatever the platform default resolves to.
    private static func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
