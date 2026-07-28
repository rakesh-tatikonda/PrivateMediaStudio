import Foundation
import CoreGraphics

/// Builds an .ass subtitle file from parsed SRT cues (reusing SRTParser from
/// the Streams tab), positioning every line at the same point/angle the user
/// set by dragging + two-finger-rotating the overlay in the Editor preview.
/// FFmpegKit's `subtitles` filter burns this in during export.
enum SRTToASSConverter {

    /// - Parameters:
    ///   - videoWidth/videoHeight: the *export* resolution — `\pos` is in
    ///     absolute pixels in ASS, so the overlay's normalized 0...1 position
    ///     has to be resolved against the actual output size, not the
    ///     on-screen preview size.
    static func convert(
        cues: [SubtitleCue],
        overlay: TextOverlayTransform,
        videoWidth: Int,
        videoHeight: Int
    ) -> String {
        let posX = Int(overlay.normalizedX * Double(videoWidth))
        let posY = Int(overlay.normalizedY * Double(videoHeight))
        // ASS rotation is counter-clockwise-positive and FFmpeg/ASS callers
        // conventionally pass \frz in degrees directly.
        let angle = overlay.rotationDegrees

        let fontSize = max(16, videoHeight / 20)

        let header = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(videoWidth)
        PlayResY: \(videoHeight)
        WrapStyle: 0
        ScaledBorderAndShadow: yes

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,\(fontSize),&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,5,10,10,10,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        let events = cues.map { cue -> String in
            let start = assTimecode(cue.startTime)
            let end = assTimecode(cue.endTime)
            let escapedText = sanitize(cue.text)
            let override = "{\\pos(\(posX),\(posY))\\frz(\(String(format: "%.1f", angle)))\\an5}"
            return "Dialogue: 0,\(start),\(end),Default,,0,0,0,,\(override)\(escapedText)"
        }.joined(separator: "\n")

        return header + "\n" + events + "\n"
    }

    /// Neutralizes ASS override-tag syntax in untrusted subtitle text.
    ///
    /// SECURITY: `{...}` opens an ASS override block that the renderer
    /// interprets as styling/positioning/animation directives — a subtitle
    /// file is untrusted input (often downloaded from third-party sites for
    /// a given video), and without this, a crafted .srt could inject its own
    /// `\pos`/`\move`/`\t` etc. tags into what's supposed to be plain dialogue
    /// text. This is exactly the bug class behind real subtitle-parsing RCEs
    /// disclosed against VLC, Kodi, and others in 2017 (malformed/malicious
    /// tag content triggering parser bugs in libass and similar renderers).
    /// Stripping `{` and `}` removes any way to *open* an override block in
    /// the first place — with no unescaped brace, a stray `\` in the
    /// remaining text is just a literal character, not a tag prefix, so this
    /// alone closes off the injection path rather than relying on further
    /// escaping of what's inside braces.
    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\N")
            .replacingOccurrences(of: "{", with: "\u{FF5B}") // fullwidth "｛" — visually similar, functionally inert
            .replacingOccurrences(of: "}", with: "\u{FF5D}") // fullwidth "｝"
    }

    static func write(cues: [SubtitleCue], overlay: TextOverlayTransform, videoWidth: Int, videoHeight: Int) -> URL? {
        let content = convert(cues: cues, overlay: overlay, videoWidth: videoWidth, videoHeight: videoHeight)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ass")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// ASS timecodes are "H:MM:SS.cc" (centiseconds), unlike SRT's
    /// "HH:MM:SS,mmm" (milliseconds) — easy to trip on if you copy SRT's format.
    private static func assTimecode(_ time: TimeInterval) -> String {
        let totalCentis = Int((time * 100).rounded())
        let hours = totalCentis / 360_000
        let minutes = (totalCentis % 360_000) / 6_000
        let seconds = (totalCentis % 6_000) / 100
        let centis = totalCentis % 100
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centis)
    }
}
