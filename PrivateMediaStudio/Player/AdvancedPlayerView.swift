import SwiftUI
import UIKit
import SwiftData

struct AdvancedPlayerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var playerViewModel: PlayerViewModel

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showSubtitleSync = false
    @State private var orientation = UIDeviceOrientation.portrait

    init(mediaItem: MediaItem, playlist: Playlist?) {
        // modelContext isn't available at init time (it's an @Environment
        // value) — PlayerViewModel instead gets a fresh ModelContext backed
        // by the same container mediaItem is already attached to, which is
        // available synchronously via PersistentModel.modelContext.
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(
            mediaItem: mediaItem, playlist: playlist, modelContext: ModelContext(mediaItem.modelContext!.container)
        ))
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let isLandscape = orientation.isLandscape

        ZStack {
            Color.black.ignoresSafeArea()

            playerCanvas

            SubtitleOverlayView(text: playerViewModel.currentSubtitleText, isLandscape: isLandscape)

            GestureZoneOverlay(
                onRewind: { playerViewModel.skip(seconds: -5) },
                onForward: { playerViewModel.skip(seconds: 5) },
                onToggleControls: toggleControls
            )

            if controlsVisible {
                controlsOverlay(theme: theme)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!controlsVisible)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientation = UIDevice.current.orientation
            scheduleAutoHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientation = UIDevice.current.orientation
        }
        .onDisappear {
            playerViewModel.stopAndSave()
            hideControlsTask?.cancel()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .sheet(isPresented: $showSubtitleSync) {
            SubtitleSyncSheet(
                playerViewModel: playerViewModel,
                activeTrack: playerViewModel.mediaItem.subtitleTracks.first { $0.id == playerViewModel.mediaItem.defaultSubtitleTrackID }
            )
        }
    }

    @ViewBuilder
    private var playerCanvas: some View {
        GeometryReader { geo in
            ZStack {
                // Exactly one VLCPlayerContainer instance, always — branching
                // it inside an if/else would change its SwiftUI identity when
                // SBS3D/VR toggle, tearing down and recreating the underlying
                // UIViewController (and the VLCMediaPlayer with it). Instead,
                // the SBS "2D from 3D" crop is applied as frame/clip values on
                // this one stable instance.
                VLCPlayerContainer(playerViewModel: playerViewModel)
                    .frame(
                        width: geo.size.width * (playerViewModel.isSBS3D ? 2 : 1),
                        height: geo.size.height
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .clipped()
                    // In VR mode the real player stays attached (so VLC keeps
                    // decoding into videoDrawableView, which the sphere below
                    // snapshots) but is visually replaced by the sphere.
                    .opacity(playerViewModel.isVRMode ? 0.001 : 1)

                if playerViewModel.isVRMode, let videoView = playerViewModel.videoDrawableView {
                    VRSphereView(sourceView: videoView)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Controls

    private func controlsOverlay(theme: AppTheme) -> some View {
        VStack {
            topBar(theme: theme)
            Spacer()
            bottomBar(theme: theme)
        }
        .background {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func topBar(theme: AppTheme) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Text(playerViewModel.mediaItem.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                playerViewModel.isSBS3D = false
                playerViewModel.isVRMode.toggle()
            } label: {
                Image(systemName: "view.3d")
                    .foregroundStyle(playerViewModel.isVRMode ? theme.accent : .white)
                    .fontWeight(playerViewModel.isVRMode ? .bold : .regular)
            }

            Button {
                playerViewModel.isVRMode = false
                playerViewModel.isSBS3D.toggle()
            } label: {
                Text("SBS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(playerViewModel.isSBS3D ? theme.accent : .white)
            }

            AirPlayButton(tintColor: .white)
                .frame(width: 28, height: 28)

            Button {
                showSubtitleSync = true
            } label: {
                Image(systemName: "captions.bubble")
                    .foregroundStyle(.white)
            }
        }
        .padding(Spacing.md)
        .padding(.top, Spacing.sm)
    }

    private func bottomBar(theme: AppTheme) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text(timeLabel(playerViewModel.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                Slider(
                    value: Binding(
                        get: { playerViewModel.duration > 0 ? playerViewModel.currentTime / playerViewModel.duration : 0 },
                        set: { playerViewModel.seek(toFraction: $0) }
                    )
                )
                .tint(theme.accent)
                Text(timeLabel(playerViewModel.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: Spacing.xl) {
                Spacer()
                if playerViewModel.isInPlaylist {
                    Button { playerViewModel.playPrevious() } label: {
                        Image(systemName: "backward.end.fill").font(.title2)
                    }
                }
                Button { playerViewModel.skip(seconds: -15) } label: {
                    Image(systemName: "gobackward.15").font(.title2)
                }
                Button { playerViewModel.togglePlayPause() } label: {
                    Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                }
                Button { playerViewModel.skip(seconds: 15) } label: {
                    Image(systemName: "goforward.15").font(.title2)
                }
                if playerViewModel.isInPlaylist {
                    Button { playerViewModel.playNext() } label: {
                        Image(systemName: "forward.end.fill").font(.title2)
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .padding(Spacing.lg)
    }

    // MARK: - Auto-hide

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
