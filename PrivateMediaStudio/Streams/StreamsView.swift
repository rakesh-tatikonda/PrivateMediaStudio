import SwiftUI
import SwiftData

struct StreamsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var viewModel = StreamsViewModel()
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MediaItem.dateAdded, order: .reverse) private var allMedia: [MediaItem]

    @AppStorage("streamsLibraryDisplayMode") private var displayModeRaw = LibraryDisplayMode.grid.rawValue
    @State private var showAddSheet = false

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(theme: theme)
                    sectionPicker(theme: theme)

                    switch viewModel.section {
                    case .allMedia:
                        allMediaSection(theme: theme)
                    case .folders:
                        FoldersView(viewModel: viewModel)
                    case .playlists:
                        PlaylistsView(viewModel: viewModel)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(theme.background)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAddSheet) {
            AddMediaSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func header(theme: AppTheme) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Streams")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primaryText)
                Text("Your library, folders, and playlists.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func sectionPicker(theme: AppTheme) -> some View {
        Picker("Section", selection: $viewModel.section) {
            ForEach(StreamsSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func allMediaSection(theme: AppTheme) -> some View {
        HStack {
            Spacer()
            Picker("Display", selection: $displayModeRaw) {
                Image(systemName: "list.bullet").tag(LibraryDisplayMode.list.rawValue)
                Image(systemName: "square.grid.2x2").tag(LibraryDisplayMode.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }

        if allMedia.isEmpty {
            emptyState(theme: theme)
        } else {
            MediaLibraryView(items: allMedia, displayMode: LibraryDisplayMode(rawValue: displayModeRaw) ?? .grid)
        }
    }

    private func emptyState(theme: AppTheme) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(theme.secondaryText)
            Text("Add your first video, stream URL, or network share.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}
