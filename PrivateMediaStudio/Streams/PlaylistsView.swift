import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: StreamsViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.dateCreated) private var playlists: [Playlist]

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                showNewPlaylistAlert = true
            } label: {
                Label("New Playlist", systemImage: "text.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))

            if playlists.isEmpty {
                Text("No playlists yet.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack {
                            Image(systemName: "music.note.list").foregroundStyle(theme.accent)
                            Text(playlist.name).foregroundStyle(theme.primaryText)
                            Spacer()
                            Text("\(playlist.orderedItems.count)")
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
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                viewModel.createPlaylist(name: newPlaylistName, modelContext: modelContext)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Bindable var playlist: Playlist

    var body: some View {
        let theme = themeManager.currentTheme
        let items = playlist.orderedItems

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let first = items.first {
                    NavigationLink {
                        // Playing from a playlist hands the whole ordered
                        // queue to the player so VLCMediaListPlayer can
                        // auto-advance (spec requirement).
                        AdvancedPlayerView(mediaItem: first, playlist: playlist)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        AdvancedPlayerView(mediaItem: item, playlist: playlist)
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(theme.secondaryText)
                                .frame(width: 20)
                            Text(item.title)
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                        }
                        .padding(Spacing.md)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.lg)
        }
        .background(theme.background)
        .navigationTitle(playlist.name)
    }
}
