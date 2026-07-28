import SwiftUI
import SwiftData

struct FoldersView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: StreamsViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaFolder.sortIndex) private var folders: [MediaFolder]

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                showNewFolderAlert = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))

            if folders.isEmpty {
                Text("No folders yet.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(folders) { folder in
                    NavigationLink {
                        FolderDetailView(folder: folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(theme.accent)
                            Text(folder.name).foregroundStyle(theme.primaryText)
                            Spacer()
                            Text("\(folder.items.count)")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(Spacing.md)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                viewModel.createFolder(name: newFolderName, modelContext: modelContext)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }
}

struct FolderDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Bindable var folder: MediaFolder
    @AppStorage("streamsLibraryDisplayMode") private var displayModeRaw = LibraryDisplayMode.grid.rawValue

    var body: some View {
        ScrollView {
            MediaLibraryView(items: folder.items, displayMode: LibraryDisplayMode(rawValue: displayModeRaw) ?? .grid)
                .padding(Spacing.lg)
        }
        .background(themeManager.currentTheme.background)
        .navigationTitle(folder.name)
    }
}
