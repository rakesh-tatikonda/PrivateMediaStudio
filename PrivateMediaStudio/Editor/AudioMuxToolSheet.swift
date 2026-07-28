import SwiftUI
import UniformTypeIdentifiers

struct AudioMuxToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel
    @State private var showFileImporter = false

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Additional Audio Tracks").font(.headline).foregroundStyle(theme.primaryText)
            Text("Each track you add here is muxed in as its own selectable audio stream (-map) alongside the video's original audio.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            Button {
                showFileImporter = true
            } label: {
                Label("Add Audio File\u{2026}", systemImage: "waveform.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))

            ForEach(viewModel.project.audioClips) { clip in
                HStack {
                    Image(systemName: "waveform").foregroundStyle(theme.accentSecondary)
                    Text(clip.displayName).foregroundStyle(theme.primaryText)
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeAudioClip(clip)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .padding(Spacing.sm)
                .cardStyle()
            }
        }
        .padding(Spacing.lg)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mp3, .wav],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didAccess = url.startAccessingSecurityScopedResource()
                viewModel.addAudioClip(from: url)
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
        }
    }
}
