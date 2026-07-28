import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct EditorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var viewModel = EditorViewModel()
    @State private var player = AVPlayer()

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            VStack(spacing: 0) {
                header(theme: theme)
                previewCanvas(theme: theme)
                TimelineView(viewModel: viewModel)
                EditorToolbar(activeTool: $viewModel.activeTool)
            }
            .background(theme.background)
            .navigationBarHidden(true)
        }
        .sheet(item: $viewModel.activeTool) { tool in
            toolSheet(for: tool)
                .environmentObject(themeManager)
                .presentationDetents(tool == .record ? [.height(280)] : [.medium, .large])
        }
        .onChange(of: viewModel.selectedClipID) { _, _ in loadPreview() }
        .onChange(of: viewModel.project.videoClips) { _, _ in loadPreview() }
    }

    private func header(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Editor")
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
            Text("Trim, grade, mux audio, burn in captions — all on-device.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
    }

    private func previewCanvas(theme: AppTheme) -> some View {
        ZStack {
            Color.black

            if viewModel.project.videoClips.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Add a clip from the Trim tool to get started.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                VideoPlayer(player: player)
            }

            if viewModel.project.subtitleSourceURL != nil {
                DraggableSubtitleOverlay(transform: $viewModel.project.subtitleOverlay)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }

    @ViewBuilder
    private func toolSheet(for tool: EditorTool) -> some View {
        switch tool {
        case .trim: TrimToolSheet(viewModel: viewModel)
        case .format: FormatToolSheet(viewModel: viewModel)
        case .audio: AudioMuxToolSheet(viewModel: viewModel)
        case .text: TextOverlayToolSheet(viewModel: viewModel)
        case .adjust: AdjustToolSheet(viewModel: viewModel)
        case .record: RecordToolSheet(recorder: viewModel.screenRecorder)
        case .export: ExportSheet(viewModel: viewModel, exporter: viewModel.exporter)
        }
    }

    private func loadPreview() {
        guard let clip = viewModel.project.videoClips.first(where: { $0.id == viewModel.selectedClipID })
            ?? viewModel.project.videoClips.first else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: clip.url))
    }
}

/// Drag-to-reposition, two-finger-rotate subtitle placeholder shown over the
/// preview. Purely a positioning UI — SRTToASSConverter reads the resulting
/// TextOverlayTransform to bake the same position/angle into the exported
/// video's burned-in captions.
private struct DraggableSubtitleOverlay: View {
    @Binding var transform: TextOverlayTransform
    @State private var dragOffset: CGSize = .zero
    @State private var rotationAtGestureStart: Double = 0

    var body: some View {
        GeometryReader { geo in
            Text("Sample Caption")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(transform.rotationDegrees))
                .position(
                    x: geo.size.width * transform.normalizedX + dragOffset.width,
                    y: geo.size.height * transform.normalizedY + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = value.translation }
                        .onEnded { value in
                            let newX = (geo.size.width * transform.normalizedX + value.translation.width) / geo.size.width
                            let newY = (geo.size.height * transform.normalizedY + value.translation.height) / geo.size.height
                            transform.normalizedX = min(max(newX, 0.05), 0.95)
                            transform.normalizedY = min(max(newY, 0.05), 0.95)
                            dragOffset = .zero
                        }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .onChanged { angle in
                            transform.rotationDegrees = rotationAtGestureStart + angle.degrees
                        }
                        .onEnded { angle in
                            rotationAtGestureStart += angle.degrees
                            transform.rotationDegrees = rotationAtGestureStart.truncatingRemainder(dividingBy: 360)
                        }
                )
        }
    }
}
