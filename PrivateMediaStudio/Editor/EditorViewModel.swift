import Foundation
import AVFoundation

enum EditorTool: String, CaseIterable, Identifiable {
    case trim = "Trim", format = "Format", audio = "Audio", text = "Text", adjust = "Adjust", record = "Record", export = "Export"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .trim: return "scissors"
        case .format: return "aspectratio"
        case .audio: return "waveform"
        case .text: return "captions.bubble"
        case .adjust: return "slider.horizontal.3"
        case .record: return "record.circle"
        case .export: return "square.and.arrow.up"
        }
    }
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project = EditorProject()
    @Published var activeTool: EditorTool?
    @Published var subtitleCues: [SubtitleCue] = []
    @Published var errorMessage: String?
    @Published var selectedClipID: UUID?

    let screenRecorder = ScreenRecorder()
    let exporter = FFmpegExporter()

    // MARK: - Clips

    /// Copies a picked file into the app's own temp working directory. Must
    /// be called while the caller's `startAccessingSecurityScopedResource()`
    /// is still active — the copy itself is synchronous specifically so nothing
    /// async happens after that access window closes. Once copied, the
    /// clip's `url` is an app-owned file needing no security scope at all,
    /// which also means trimming/export can safely happen minutes later in
    /// the editing session without re-resolving anything.
    private func copyToWorkingDirectory(from sourceURL: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorImport-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    /// Call with the picked URL's security scope still active (i.e. before
    /// your `stopAccessingSecurityScopedResource()`).
    func addVideoClip(from pickedURL: URL) {
        guard let localURL = try? copyToWorkingDirectory(from: pickedURL) else {
            errorMessage = "Couldn't import that video."
            return
        }
        Task {
            let asset = AVURLAsset(url: localURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let clip = EditorClip(
                url: localURL,
                displayName: pickedURL.deletingPathExtension().lastPathComponent,
                sourceDuration: duration,
                trimStart: 0,
                trimEnd: duration
            )
            project.videoClips.append(clip)
            if selectedClipID == nil { selectedClipID = clip.id }
        }
    }

    /// Call with the picked URL's security scope still active.
    func addAudioClip(from pickedURL: URL) {
        guard let localURL = try? copyToWorkingDirectory(from: pickedURL) else {
            errorMessage = "Couldn't import that audio file."
            return
        }
        Task {
            let asset = AVURLAsset(url: localURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let clip = EditorClip(
                url: localURL,
                displayName: pickedURL.deletingPathExtension().lastPathComponent,
                sourceDuration: duration,
                trimStart: 0,
                trimEnd: duration
            )
            project.audioClips.append(clip)
        }
    }

    func removeAudioClip(_ clip: EditorClip) {
        project.audioClips.removeAll { $0.id == clip.id }
        try? FileManager.default.removeItem(at: clip.url)
    }

    func updateTrim(for clipID: UUID, start: Double, end: Double) {
        guard let index = project.videoClips.firstIndex(where: { $0.id == clipID }) else { return }
        project.videoClips[index].trimStart = max(0, start)
        project.videoClips[index].trimEnd = min(project.videoClips[index].sourceDuration, end)
    }

    func removeClip(_ clip: EditorClip) {
        project.videoClips.removeAll { $0.id == clip.id }
        if selectedClipID == clip.id { selectedClipID = project.videoClips.first?.id }
        try? FileManager.default.removeItem(at: clip.url)
    }

    // MARK: - Subtitles

    func loadSubtitle(from url: URL) {
        project.subtitleSourceURL = url
        subtitleCues = SRTParser.parse(fileAt: url)
    }

    func clearSubtitle() {
        project.subtitleSourceURL = nil
        subtitleCues = []
    }

    // MARK: - Export

    func export() async {
        guard !project.isEmpty else {
            errorMessage = "Add a video clip before exporting."
            return
        }
        let result = await exporter.export(project: project, subtitleCues: subtitleCues)
        if case .failure(let error) = result {
            errorMessage = error.localizedDescription
        }
    }
}
