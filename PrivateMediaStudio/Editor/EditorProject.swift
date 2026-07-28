import Foundation
import CoreGraphics

/// A single clip placed on the timeline. Kept intentionally simple (one
/// trim range per clip, sequential placement) — enough to drive a real
/// FFmpeg export without building a full nonlinear compositing engine.
struct EditorClip: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var displayName: String
    var sourceDuration: Double        // full duration of the underlying asset, seconds
    var trimStart: Double = 0
    var trimEnd: Double

    var trimmedDuration: Double { max(0, trimEnd - trimStart) }
}

enum EditorResolution: Equatable, Identifiable {
    case p480, p720, p1080, p4k
    case custom(width: Int, height: Int)

    var id: String {
        switch self {
        case .p480: return "480p"
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p4k: return "4K"
        case .custom(let w, let h): return "\(w)x\(h)"
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .p480: return (854, 480)
        case .p720: return (1280, 720)
        case .p1080: return (1920, 1080)
        case .p4k: return (3840, 2160)
        case .custom(let w, let h): return (w, h)
        }
    }
}

/// The 11 grading sliders from the spec, each normalized to -1...1 (0 = no
/// change) except Vignette, which is 0...1 (0 = off). FFmpegCommandBuilder
/// maps these onto real FFmpeg filters — see its doc comments for exactly
/// which filter each one drives.
struct ColorGradingSettings: Equatable {
    var brightness: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var saturation: Double = 0
    var vibrance: Double = 0
    var warmth: Double = 0
    var sharpness: Double = 0
    var clarity: Double = 0
    var vignette: Double = 0

    var isIdentity: Bool { self == ColorGradingSettings() }
}

/// Position/rotation of the burned-in subtitle block, set by dragging +
/// two-finger rotating it in the preview. Normalized 0...1 so it's
/// independent of preview canvas size vs. the actual export resolution.
struct TextOverlayTransform: Equatable {
    var normalizedX: Double = 0.5
    var normalizedY: Double = 0.85
    var rotationDegrees: Double = 0
}

/// Root editing state for one export. Everything FFmpegCommandBuilder needs
/// lives here — kept as a plain observable struct-holder on
/// EditorViewModel rather than SwiftData, since a work-in-progress edit
/// isn't something the spec asks to persist across launches (unlike the
/// Streams library).
struct EditorProject {
    var videoClips: [EditorClip] = []
    var audioClips: [EditorClip] = []   // additional muxed-in audio tracks
    var subtitleSourceURL: URL?
    var subtitleOverlay = TextOverlayTransform()
    var colorGrading = ColorGradingSettings()
    var resolution: EditorResolution = .p1080

    var totalVideoDuration: Double {
        videoClips.reduce(0) { $0 + $1.trimmedDuration }
    }

    var isEmpty: Bool { videoClips.isEmpty }
}
