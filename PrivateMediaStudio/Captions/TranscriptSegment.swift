import Foundation

/// One line of a transcript. Times are seconds from the start of the audio.
struct TranscriptSegment: Identifiable, Hashable {
    let id = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    var timecodeLabel: String {
        String(format: "%02d:%02d", Int(startTime) / 60, Int(startTime) % 60)
    }
}
