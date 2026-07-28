import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct AddMediaSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: StreamsViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var showFileImporter = false
    @State private var showSubtitleImporter = false
    @State private var showServerSheet = false
    @State private var pendingLocalItemForSubtitle: MediaItem?

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            Form {
                Section("Add via URL") {
                    HStack {
                        TextField("https://... (direct link or .m3u8)", text: $urlText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            viewModel.addMediaViaURL(urlText, modelContext: modelContext)
                            urlText = ""
                            dismiss()
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Add Local Video") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose from Files\u{2026}", systemImage: "folder.badge.plus")
                    }
                }

                Section("Network Servers") {
                    Button {
                        showServerSheet = true
                    } label: {
                        Label("Connect to Server (SMB/FTP)\u{2026}", systemImage: "externaldrive.badge.wifi")
                    }
                }
            }
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(theme.accent)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            if let newItem = viewModel.addLocalVideo(pickedURL: url, modelContext: modelContext) {
                pendingLocalItemForSubtitle = newItem
            }
        }
        .alert(
            "Attach a Subtitle?",
            isPresented: Binding(
                get: { pendingLocalItemForSubtitle != nil },
                set: { if !$0 { pendingLocalItemForSubtitle = nil } }
            )
        ) {
            Button("Attach .srt\u{2026}") { showSubtitleImporter = true }
            Button("Skip", role: .cancel) {
                pendingLocalItemForSubtitle = nil
                dismiss()
            }
        } message: {
            Text("Pair a local .srt file with this video now — it'll auto-load every time you play it.")
        }
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first, let item = pendingLocalItemForSubtitle {
                viewModel.attachSubtitle(pickedURL: url, to: item, modelContext: modelContext)
            }
            pendingLocalItemForSubtitle = nil
            dismiss()
        }
        .sheet(isPresented: $showServerSheet) {
            SMBFTPConnectionSheet(viewModel: viewModel)
        }
    }
}

/// Shown from a MediaItem's context menu — "Attach Local Subtitle" after
/// creation, or the equivalent flow can be reached at creation time by adding
/// a local video and then immediately attaching a subtitle to it.
struct AttachSubtitleSheet: View {
    @ObservedObject var viewModel: StreamsViewModel
    let mediaItem: MediaItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = true

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.attachSubtitle(pickedURL: url, to: mediaItem, modelContext: modelContext)
                }
                dismiss()
            }
    }
}
