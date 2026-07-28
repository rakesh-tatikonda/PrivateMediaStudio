import SwiftUI
import UniformTypeIdentifiers

struct TrimToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel
    @State private var showFileImporter = false

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.lg) {
            Button {
                showFileImporter = true
            } label: {
                Label("Add Clip\u{2026}", systemImage: "plus.rectangle.on.folder")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))

            if let clipID = viewModel.selectedClipID,
               let index = viewModel.project.videoClips.firstIndex(where: { $0.id == clipID }) {
                let clip = viewModel.project.videoClips[index]

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(clip.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Start: \(timeLabel(clip.trimStart))")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Slider(
                        value: Binding(
                            get: { clip.trimStart },
                            set: { viewModel.updateTrim(for: clip.id, start: $0, end: clip.trimEnd) }
                        ),
                        in: 0...max(0.1, clip.trimEnd - 0.1)
                    )

                    Text("End: \(timeLabel(clip.trimEnd))")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Slider(
                        value: Binding(
                            get: { clip.trimEnd },
                            set: { viewModel.updateTrim(for: clip.id, start: clip.trimStart, end: $0) }
                        ),
                        in: min(clip.sourceDuration, clip.trimStart + 0.1)...clip.sourceDuration
                    )

                    Button(role: .destructive) {
                        viewModel.removeClip(clip)
                    } label: {
                        Label("Remove Clip", systemImage: "trash")
                    }
                }
                .tint(theme.accent)
            } else {
                Text("Select a clip on the timeline to trim it.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(Spacing.lg)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didAccess = url.startAccessingSecurityScopedResource()
                viewModel.addVideoClip(from: url)
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
