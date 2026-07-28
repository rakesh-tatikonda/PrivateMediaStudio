import SwiftUI
import UniformTypeIdentifiers

struct SubtitleSyncSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var playerViewModel: PlayerViewModel
    let activeTrack: SubtitleTrack?
    @Environment(\.dismiss) private var dismiss

    @State private var offset: Double
    @State private var showSubtitleImporter = false

    init(playerViewModel: PlayerViewModel, activeTrack: SubtitleTrack?) {
        self.playerViewModel = playerViewModel
        self.activeTrack = activeTrack
        _offset = State(initialValue: playerViewModel.subtitleSyncOffset)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text(String(format: "%+.2fs", offset))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(theme.primaryText)

                Slider(value: $offset, in: -600...600, step: 0.25)
                    .tint(theme.accent)
                    .onChange(of: offset) { _, newValue in
                        playerViewModel.updateSyncOffset(newValue, persistTo: activeTrack)
                    }

                HStack(spacing: Spacing.lg) {
                    microButton("-0.25s") { adjust(-0.25) }
                    microButton("+0.25s") { adjust(0.25) }
                }

                Button {
                    showSubtitleImporter = true
                } label: {
                    Label("Load a Different Subtitle\u{2026}", systemImage: "captions.bubble")
                }
                .buttonStyle(PrimaryButtonStyle())

                Spacer()
            }
            .padding(Spacing.lg)
            .background(theme.background)
            .navigationTitle("Subtitle Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didAccess = url.startAccessingSecurityScopedResource()
                playerViewModel.loadSubtitle(from: url)
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private func microButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(themeManager.currentTheme.accent)
    }

    private func adjust(_ delta: Double) {
        offset = max(-600, min(600, offset + delta))
        playerViewModel.updateSyncOffset(offset, persistTo: activeTrack)
    }
}
