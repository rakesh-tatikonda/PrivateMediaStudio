import SwiftUI

/// A simplified but real multi-track timeline: each track is a horizontal
/// row of proportionally-sized blocks (width ∝ trimmed duration). Tapping a
/// video clip selects it for the Trim tool; this isn't a full drag-to-reorder
/// NLE canvas, but it accurately reflects what will actually export.
struct TimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel

    private let pixelsPerSecond: CGFloat = 24

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                trackRow(title: "Video", theme: theme) {
                    HStack(spacing: 2) {
                        ForEach(viewModel.project.videoClips) { clip in
                            clipBlock(
                                title: clip.displayName,
                                width: max(40, CGFloat(clip.trimmedDuration) * pixelsPerSecond),
                                color: theme.accent,
                                isSelected: viewModel.selectedClipID == clip.id
                            )
                            .onTapGesture {
                                viewModel.selectedClipID = clip.id
                                viewModel.activeTool = .trim
                            }
                        }
                        if viewModel.project.videoClips.isEmpty {
                            emptyTrackHint("No video yet — use Trim's Add Clip")
                        }
                    }
                }

                trackRow(title: "Audio", theme: theme) {
                    HStack(spacing: 2) {
                        ForEach(viewModel.project.audioClips) { clip in
                            clipBlock(
                                title: clip.displayName,
                                width: max(40, CGFloat(clip.trimmedDuration) * pixelsPerSecond),
                                color: theme.accentSecondary,
                                isSelected: false
                            )
                        }
                        if viewModel.project.audioClips.isEmpty {
                            emptyTrackHint("No extra audio tracks")
                        }
                    }
                }

                trackRow(title: "Subtitle", theme: theme) {
                    if viewModel.project.subtitleSourceURL != nil {
                        clipBlock(
                            title: "\(viewModel.subtitleCues.count) cues",
                            width: max(80, CGFloat(viewModel.project.totalVideoDuration) * pixelsPerSecond),
                            color: theme.accent.opacity(0.6),
                            isSelected: false
                        )
                    } else {
                        emptyTrackHint("No subtitle loaded")
                    }
                }
            }
            .padding(Spacing.md)
        }
        .frame(height: 150)
        .background(theme.surfaceColor.opacity(0.5))
    }

    private func trackRow<Content: View>(title: String, theme: AppTheme, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 56, alignment: .leading)
            content()
        }
    }

    private func clipBlock(title: String, width: CGFloat, color: Color, isSelected: Bool) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: width, height: 36, alignment: .leading)
            .background(color.opacity(isSelected ? 1 : 0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                }
            }
    }

    private func emptyTrackHint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(themeManager.currentTheme.secondaryText)
            .frame(height: 36)
    }
}
