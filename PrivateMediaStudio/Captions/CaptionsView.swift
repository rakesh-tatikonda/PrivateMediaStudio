import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CaptionsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var viewModel = CaptionsViewModel()
    @State private var showFileImporter = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(theme: theme)
                    inputModeSection(theme: theme)
                    optionsSection(theme: theme)

                    if viewModel.isProcessing {
                        progressSection(theme: theme)
                    }

                    transcriptSection(theme: theme)

                    if !viewModel.segments.isEmpty {
                        exportSection(theme: theme)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(theme.background)
            .navigationBarHidden(true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie, .video, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.processLocalFile(at: url)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("OK") { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .sheet(isPresented: $showExportSheet) {
            if let exportedFileURL {
                ShareSheet(items: [exportedFileURL])
            }
        }
    }

    // MARK: - Sections

    private func header(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Captions")
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
            Text("Transcribe and translate, entirely on-device.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func inputModeSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Input", selection: $viewModel.inputMode) {
                ForEach(CaptionsInputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.inputMode {
            case .file:
                Button("Choose File\u{2026}") { showFileImporter = true }
                    .buttonStyle(PrimaryButtonStyle())

            case .liveMic:
                Button {
                    if viewModel.liveMicRecorder.isRecording {
                        viewModel.stopLiveMic()
                    } else {
                        viewModel.startLiveMic()
                    }
                } label: {
                    Label(
                        viewModel.liveMicRecorder.isRecording ? "Stop Recording" : "Start Recording",
                        systemImage: viewModel.liveMicRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())

            case .url:
                HStack {
                    TextField("Paste a media URL", text: $viewModel.mediaURLText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Go") { viewModel.processMediaURL() }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
    }

    private func optionsSection(theme: AppTheme) -> some View {
        VStack(spacing: Spacing.sm) {
            Toggle("Live Translate to English", isOn: $viewModel.translateToEnglish)
            HStack {
                Text("Language")
                Spacer()
                Picker("Language", selection: $viewModel.selectedLanguage) {
                    ForEach(CaptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(Spacing.lg)
        .cardStyle()
        .tint(theme.accent)
    }

    private func progressSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ProgressView(value: viewModel.progress)
                .tint(theme.accent)
            Text("Transcribing\u{2026}")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(Spacing.lg)
        .cardStyle()
    }

    @ViewBuilder
    private func transcriptSection(theme: AppTheme) -> some View {
        let displaySegments = viewModel.inputMode == .liveMic ? viewModel.liveMicRecorder.liveSegments : viewModel.segments

        if !displaySegments.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(displaySegments) { segment in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text(segment.timecodeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, alignment: .leading)
                        Text(segment.text)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            .padding(Spacing.lg)
            .cardStyle()
        } else if !viewModel.isProcessing {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "text.quote")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.secondaryText)
                Text("Your transcript will appear here.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
        }
    }

    private func exportSection(theme: AppTheme) -> some View {
        HStack(spacing: Spacing.sm) {
            exportButton(title: ".txt") { viewModel.exportTXT() }
            exportButton(title: ".srt") { viewModel.exportSRT() }
            exportButton(title: ".m4a") { viewModel.exportM4A() }
        }
    }

    private func exportButton(title: String, action: @escaping () -> URL?) -> some View {
        Button(title) {
            if let url = action() {
                exportedFileURL = url
                showExportSheet = true
            }
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
    }
}

/// Thin UIActivityViewController wrapper so exported files can be shared/saved
/// via the standard iOS share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
