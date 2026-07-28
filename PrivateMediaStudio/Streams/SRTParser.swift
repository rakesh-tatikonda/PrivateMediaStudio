import Foundation

struct SubtitleCue: Identifiable {
    let id = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
}

/// Parses standard .srt into cues. The player renders subtitles itself (see
/// SubtitleOverlayView) rather than relying on VLCKit's internal subtitle
/// renderer, because the spec's alignment presets (1-7) and a live
/// -600s..+600s sync slider are both easiest to get right when Swift owns
/// cue timing and layout directly, instead of round-tripping settings into
/// libvlc's ASS/SSA styling pipeline.
enum SRTParser {

    /// Real .srt files for even very long content are a few hundred KB at
    /// most. Subtitle files are routinely downloaded from third-party sites
    /// for a given piece of media, i.e. untrusted input — capping the read
    /// bounds how much memory a crafted oversized file can force the app to
    /// allocate, rather than trusting file size implicitly.
    private static let maxFileSize = 10 * 1024 * 1024 // 10MB

    static func parse(fileAt url: URL) -> [SubtitleCue] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int, fileSize <= maxFileSize else {
            return []
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            // .srt files are sometimes Latin-1/Windows-1252 in the wild.
            guard let fallback = try? String(contentsOf: url, encoding: .isoLatin1) else { return [] }
            return parse(text: fallback)
        }
        return parse(text: contents)
    }

    static func parse(text: String) -> [SubtitleCue] {
        // Blocks are separated by a blank line: index, timecode line, text line(s).
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard lines.count >= 2 else { continue }

            // Find the timecode line (index line is optional/sometimes missing).
            guard let timecodeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timecodeLine = lines[timecodeLineIndex]
            let textLines = lines[(timecodeLineIndex + 1)...]

            guard let (start, end) = parseTimecodeLine(timecodeLine) else { continue }
            let text = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // strip basic HTML-ish tags

            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(startTime: start, endTime: end, text: text))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    private static func parseTimecodeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimecode(parts[0]),
              let end = parseTimecode(parts[1]) else { return nil }
        return (start, end)
    }

    /// Parses "HH:MM:SS,mmm" (or with '.' instead of ',').
    private static func parseTimecode(_ raw: String) -> TimeInterval? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        let normalized = cleaned.replacingOccurrences(of: ".", with: ",")
        let mainParts = normalized.split(separator: ",")
        guard mainParts.count == 2,
              let millis = Double(mainParts[1]) else { return nil }

        let hms = mainParts[0].split(separator: ":").compactMap { Double($0) }
        guard hms.count == 3 else { return nil }

        return hms[0] * 3600 + hms[1] * 60 + hms[2] + millis / 1000.0
    }
}
