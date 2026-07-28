import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var exporter: FFmpegExporter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(spacing: Spacing.lg) {
            Text("Export").font(.headline).foregroundStyle(theme.primaryText)

            summaryRow(theme: theme)

            if exporter.isExporting {
                VStack(spacing: Spacing.sm) {
                    ProgressView(value: exporter.progress)
                        .tint(theme.accent)
                    Text(exporter.statusMessage ?? "Working\u{2026}")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Button("Cancel", role: .destructive) { exporter.cancel() }
                        .font(.caption)
                }
            } else {
                Button {
                    Task { await viewModel.export() }
                } label: {
                    Label("Export to Photos", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.project.isEmpty)
            }

            if let status = exporter.statusMessage, status == "Done" {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(Spacing.lg)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func summaryRow(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let (w, h) = viewModel.project.resolution.dimensions
            summaryLine("Resolution", "\(w)\u{00D7}\(h)", theme: theme)
            summaryLine("Video clips", "\(viewModel.project.videoClips.count)", theme: theme)
            summaryLine("Audio tracks", "\(viewModel.project.audioClips.count) extra", theme: theme)
            summaryLine("Subtitles", viewModel.project.subtitleSourceURL != nil ? "Burned in" : "None", theme: theme)
            summaryLine("Grading", viewModel.project.colorGrading.isIdentity ? "None" : "Applied", theme: theme)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private func summaryLine(_ label: String, _ value: String, theme: AppTheme) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.secondaryText)
            Spacer()
            Text(value).foregroundStyle(theme.primaryText)
        }
        .font(.caption)
    }
}
