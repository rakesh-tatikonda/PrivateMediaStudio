import Foundation
import UIKit
import SwiftUI
import SwiftData
import MobileVLCKit

/// Drives playback for one MediaItem, optionally within a Playlist queue.
/// Owns the actual VLCMediaPlayer (or VLCMediaListPlayer when a playlist is
/// supplied) so SwiftUI controls can call into it directly. Subtitles are
/// rendered by SwiftUI (see SubtitleOverlayView), not VLC's internal
/// renderer — see SRTParser's doc comment for why.
@MainActor
final class PlayerViewModel: NSObject, ObservableObject {

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentSubtitleText: String?
    @Published var isVRMode = false
    @Published var isSBS3D = false
    @Published var errorMessage: String?

    private(set) var mediaItem: MediaItem
    private let playlist: Playlist?
    private let modelContext: ModelContext

    private var mediaPlayer: VLCMediaPlayer?
    private var listPlayer: VLCMediaListPlayer?

    /// The actual UIView VLC renders into. VRSphereView snapshots this
    /// directly — passing any other view would just capture blank content.
    private(set) var videoDrawableView: UIView?

    private var subtitleCues: [SubtitleCue] = []
    var subtitleSyncOffset: TimeInterval = 0 {
        didSet { updateCurrentSubtitle() }
    }

    private var progressSaveTimer: Timer?

    init(mediaItem: MediaItem, playlist: Playlist?, modelContext: ModelContext) {
        self.mediaItem = mediaItem
        self.playlist = playlist
        self.modelContext = modelContext
        super.init()
    }

    // MARK: - Setup

    /// Called once the VLC drawable UIView exists (from VLCPlayerContainer).
    /// Guarded to run exactly once: VLCPlayerContainer's makeUIViewController
    /// only fires once per SwiftUI identity in normal use, but this guard
    /// makes that an invariant rather than an assumption — a second
    /// VLCMediaPlayer pointed at the same media would fight the first one
    /// for the drawable and audio session.
    func attachDrawable(_ view: UIView) {
        guard mediaPlayer == nil else { return }
        videoDrawableView = view

        let cachingMs = UserDefaults.standard.object(forKey: AppStorageKeys.streamsBufferingMs) != nil
            ? UserDefaults.standard.integer(forKey: AppStorageKeys.streamsBufferingMs)
            : 1500

        if let playlist, !playlist.orderedItems.isEmpty {
            let list = VLCMediaList()
            for item in playlist.orderedItems {
                guard let url = resolvedURL(for: item) else { continue }
                let media = VLCMedia(url: url)
                media.addOptions(["network-caching": cachingMs])
                list.add(media)
            }
            let player = VLCMediaListPlayer()
            player.mediaList = list
            player.mediaPlayer.drawable = view
            player.delegate = self
            player.mediaPlayer.delegate = self
            self.listPlayer = player
            self.mediaPlayer = player.mediaPlayer

            if let startIndex = playlist.orderedItems.firstIndex(where: { $0.id == mediaItem.id }) {
                player.play(itemAtIndex: Int32(startIndex))
            } else {
                player.play()
            }
        } else {
            guard let url = resolvedURL(for: mediaItem) else {
                errorMessage = "Couldn't resolve a playable URL for this item."
                return
            }
            let media = VLCMedia(url: url)
            media.addOptions(["network-caching": cachingMs])
            let player = VLCMediaPlayer()
            player.media = media
            player.drawable = view
            player.delegate = self
            self.mediaPlayer = player
            player.play()
        }

        loadDefaultSubtitleIfNeeded()
        seekToResumePosition()
        startProgressSaveTimer()
    }

    private func resolvedURL(for item: MediaItem) -> URL? {
        switch item.sourceType {
        case .localFile:
            return item.resolveLocalURL()
        case .remoteURL:
            return item.remoteURLString.flatMap(URL.init(string:))
        case .smb, .ftp:
            guard let connectionID = item.serverConnectionID else { return nil }
            let descriptor = FetchDescriptor<ServerConnection>(predicate: #Predicate { $0.id == connectionID })
            guard let connection = try? modelContext.fetch(descriptor).first,
                  let base = try? connection.mediaURL(),
                  let relativePath = item.remoteURLString else { return nil }
            return base.appendingPathComponent(relativePath)
        }
    }

    // MARK: - Transport controls

    func togglePlayPause() {
        guard let mediaPlayer else { return }
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    func seek(toFraction fraction: Double) {
        mediaPlayer?.position = Float(fraction)
    }

    func skip(seconds: Int32) {
        guard let mediaPlayer else { return }
        if seconds >= 0 {
            mediaPlayer.jumpForward(seconds)
        } else {
            mediaPlayer.jumpBackward(-seconds)
        }
    }

    func playNext() { listPlayer?.next() }
    func playPrevious() { listPlayer?.previous() }
    var isInPlaylist: Bool { listPlayer != nil }

    // MARK: - Subtitles

    private func loadDefaultSubtitleIfNeeded() {
        guard let defaultID = mediaItem.defaultSubtitleTrackID,
              let track = mediaItem.subtitleTracks.first(where: { $0.id == defaultID }),
              let url = track.resolveURL() else { return }
        subtitleSyncOffset = track.syncOffsetSeconds
        subtitleCues = SRTParser.parse(fileAt: url)
    }

    /// Loads a new local .srt on the fly (spec: "allow loading a new local
    /// .srt on the fly"), independent of whatever was auto-attached.
    func loadSubtitle(from url: URL) {
        subtitleCues = SRTParser.parse(fileAt: url)
    }

    func updateSyncOffset(_ offset: TimeInterval, persistTo track: SubtitleTrack?) {
        subtitleSyncOffset = offset
        if let track {
            track.syncOffsetSeconds = offset
            try? modelContext.save()
        }
    }

    private func updateCurrentSubtitle() {
        let adjusted = currentTime - subtitleSyncOffset
        currentSubtitleText = subtitleCues.first { adjusted >= $0.startTime && adjusted <= $0.endTime }?.text
    }

    // MARK: - Resume / progress persistence

    private func seekToResumePosition() {
        guard mediaItem.lastPlaybackPositionSeconds > 1 else { return }
        // VLC needs a moment after play() before position sets take effect
        // reliably (media isn't "parsed" instantaneously) — a short delay
        // is the pragmatic real-world fix used broadly with VLCKit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let mediaPlayer = self.mediaPlayer, let vlcDuration = mediaPlayer.media?.length.intValue, vlcDuration > 0 else { return }
            let fraction = self.mediaItem.lastPlaybackPositionSeconds / (Double(vlcDuration) / 1000.0)
            mediaPlayer.position = Float(fraction)
        }
    }

    private func startProgressSaveTimer() {
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.persistProgress() }
        }
    }

    private func persistProgress() {
        guard mediaPlayer != nil else { return }
        mediaItem.lastPlaybackPositionSeconds = currentTime
        if duration > 0 {
            mediaItem.watchedFraction = min(max(currentTime / duration, 0), 1)
        }
        if mediaItem.durationSeconds == nil, duration > 0 {
            mediaItem.durationSeconds = duration
        }
        try? modelContext.save()
    }

    func stopAndSave() {
        persistProgress()
        progressSaveTimer?.invalidate()
        mediaPlayer?.stop()
    }

    deinit {
        progressSaveTimer?.invalidate()
    }
}

// MARK: - VLCMediaPlayerDelegate

extension PlayerViewModel: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let mediaPlayer else { return }
            isPlaying = mediaPlayer.isPlaying
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let mediaPlayer else { return }
            currentTime = Double(mediaPlayer.time.intValue) / 1000.0
            if let length = mediaPlayer.media?.length.intValue, length > 0 {
                duration = Double(length) / 1000.0
            }
            updateCurrentSubtitle()
        }
    }
}

// MARK: - VLCMediaListPlayerDelegate

extension PlayerViewModel: VLCMediaListPlayerDelegate {
    nonisolated func mediaListPlayerFinishedPlayback(_ mediaListPlayer: VLCMediaListPlayer) {
        // Whole queue finished — nothing extra needed; VLCMediaListPlayer
        // already auto-advances between items per spec.
    }
}
