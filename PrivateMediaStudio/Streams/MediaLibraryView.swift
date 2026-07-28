import SwiftUI
import SwiftData
import UIKit

struct MediaLibraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    let items: [MediaItem]
    let displayMode: LibraryDisplayMode

    @StateObject private var streamsViewModel = StreamsViewModel()
    @State private var subtitleTargetItem: MediaItem?

    private let gridColumns = [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)]

    var body: some View {
        Group {
            switch displayMode {
            case .grid:
                LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                    ForEach(items) { item in
                        cell(for: item) { GridCell(item: item) }
                    }
                }

            case .list:
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(items) { item in
                        cell(for: item) { ListRow(item: item) }
                    }
                }
            }
        }
        .sheet(item: $subtitleTargetItem) { item in
            AttachSubtitleSheet(viewModel: streamsViewModel, mediaItem: item)
        }
    }

    @ViewBuilder
    private func cell<Content: View>(for item: MediaItem, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink {
            AdvancedPlayerView(mediaItem: item, playlist: nil)
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                subtitleTargetItem = item
            } label: {
                Label("Attach Subtitle\u{2026}", systemImage: "captions.bubble")
            }
            Button(role: .destructive) {
                streamsViewModel.delete(item, modelContext: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct GridCell: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: MediaItem
    @State private var thumbnail: UIImage?

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(theme.surfaceColor)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        } else {
                            Image(systemName: sourceIcon)
                                .font(.system(size: 24))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                if item.watchedFraction > 0.02 {
                    ProgressBarStrip(fraction: item.watchedFraction, accent: theme.accent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            Text(item.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
        }
        .task { thumbnail = ThumbnailGenerator.existingThumbnail(for: item) }
    }

    private var sourceIcon: String {
        switch item.sourceType {
        case .localFile: return "film"
        case .remoteURL: return "antenna.radiowaves.left.and.right"
        case .smb, .ftp: return "externaldrive.badge.wifi"
        }
    }
}

private struct ListRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: MediaItem
    @State private var thumbnail: UIImage?

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(spacing: Spacing.md) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.surfaceColor)
                    .frame(width: 84, height: 48)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 84, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                if item.watchedFraction > 0.02 {
                    ProgressBarStrip(fraction: item.watchedFraction, accent: theme.accent)
                        .frame(height: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                if let duration = item.durationSeconds {
                    Text(formatted(duration))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .cardStyle()
        .task { thumbnail = ThumbnailGenerator.existingThumbnail(for: item) }
    }

    private func formatted(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Thin progress strip drawn along the bottom edge of a thumbnail, per spec
/// ("visual progress bar directly on the media thumbnails in both List and
/// Grid views"). Renders as a segmented LED meter for the Retro theme.
private struct ProgressBarStrip: View {
    @EnvironmentObject var themeManager: ThemeManager
    let fraction: Double
    let accent: Color

    var body: some View {
        Group {
            if themeManager.currentTheme == .retro {
                RetroLEDProgressBar(fraction: fraction, color: accent, segmentCount: 10)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black.opacity(0.35))
                        Rectangle().fill(accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
            }
        }
        .frame(height: 3)
    }
}
