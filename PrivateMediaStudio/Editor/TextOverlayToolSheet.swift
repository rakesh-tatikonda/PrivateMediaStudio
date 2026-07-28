import SwiftUI
import UniformTypeIdentifiers

struct TextOverlayToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel
    @State private var showFileImporter = false

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Subtitle Burn-In").font(.headline).foregroundStyle(theme.primaryText)

            if let url = viewModel.project.subtitleSourceURL {
                HStack {
                    Image(systemName: "captions.bubble.fill").foregroundStyle(theme.accent)
                    Text(url.lastPathComponent).foregroundStyle(theme.primaryText)
                    Spacer()
                    Button(role: .destructive) { viewModel.clearSubtitle() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .padding(Spacing.sm)
                .cardStyle()

                Text("Drag the caption preview on the video above to reposition it, and rotate with a two-finger twist. Its position is baked in exactly at export time.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)

                HStack {
                    Text("Rotation")
                    Spacer()
                    Text("\(Int(viewModel.project.subtitleOverlay.rotationDegrees))\u{00B0}")
                        .foregroundStyle(theme.secondaryText)
                }
                Button("Reset Position") {
                    viewModel.project.subtitleOverlay = TextOverlayTransform()
                }
                .font(.caption)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Load .srt\u{2026}", systemImage: "captions.bubble")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            }
        }
        .padding(Spacing.lg)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didAccess = url.startAccessingSecurityScopedResource()
                if let localURL = try? copyLocally(url) {
                    viewModel.loadSubtitle(from: localURL)
                }
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    /// Same reasoning as EditorViewModel's video/audio import: copy while the
    /// security scope is still open so the file remains readable at export
    /// time, minutes later in the session.
    private func copyLocally(_ url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorImport-\(UUID().uuidString)")
            .appendingPathExtension("srt")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
