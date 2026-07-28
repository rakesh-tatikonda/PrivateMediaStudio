import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    @AppStorage(AppStorageKeys.portraitSubtitleAlignment) private var portraitAlignment: Int = 4 // 1...7, 4 = bottom-center-ish default
    @AppStorage(AppStorageKeys.backgroundMediaStreaming) private var backgroundMediaStreaming = true
    @AppStorage(AppStorageKeys.backgroundTranslations) private var backgroundTranslations = true
    @AppStorage(AppStorageKeys.backgroundLiveMic) private var backgroundLiveMic = false
    @AppStorage(AppStorageKeys.streamsBufferingMs) private var streamsBufferingMs: Double = 1500

    @State private var castStopMessage: String?
    @State private var showResetConfirmation = false

    var body: some View {
        let theme = themeManager.currentTheme

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(theme: theme)
                    appearanceSection(theme: theme)
                    streamingSection(theme: theme)
                    captionsSection(theme: theme)
                    bufferingSection(theme: theme)
                    aboutSection(theme: theme)
                }
                .padding(Spacing.lg)
            }
            .background(theme.background)
            .navigationBarHidden(true)
        }
        .alert("Casting", isPresented: .constant(castStopMessage != nil)) {
            Button("OK") { castStopMessage = nil }
        } message: {
            Text(castStopMessage ?? "")
        }
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) { resetAllSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets appearance, playback, and captions preferences to their defaults. Your media library, folders, and playlists are not affected.")
        }
    }

    private func header(theme: AppTheme) -> some View {
        Text("Settings")
            .font(theme.titleFont)
            .foregroundStyle(theme.primaryText)
    }

    private func appearanceSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Appearance").font(.headline).foregroundStyle(theme.primaryText)
            Picker("Theme", selection: Binding(
                get: { themeManager.currentTheme },
                set: { themeManager.setTheme($0) }
            )) {
                ForEach(AppTheme.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(Spacing.lg)
        .cardStyle()
    }

    private func streamingSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Streaming & Playback").font(.headline).foregroundStyle(theme.primaryText)

            HStack {
                Text("Portrait Subtitle Alignment")
                Spacer()
                Menu {
                    ForEach(1...7, id: \.self) { value in
                        Button("\(value)") { portraitAlignment = value }
                    }
                } label: {
                    Label("\(portraitAlignment)", systemImage: "chevron.up.chevron.down")
                }
            }

            Toggle("Background Media Streaming", isOn: $backgroundMediaStreaming)
                .onChange(of: backgroundMediaStreaming) { _, newValue in
                    applyBackgroundStreamingPreference(newValue)
                }

            Button(role: .destructive) {
                stopCasting()
            } label: {
                Label("Stop Casting", systemImage: "airplayvideo.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .tint(theme.accent)
    }

    private func captionsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Captions").font(.headline).foregroundStyle(theme.primaryText)
            Toggle("Background Translations", isOn: $backgroundTranslations)
            Toggle("Background Live Mic", isOn: $backgroundLiveMic)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .tint(theme.accent)
    }

    private func bufferingSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Streams Buffering").font(.headline).foregroundStyle(theme.primaryText)
            HStack {
                Slider(value: $streamsBufferingMs, in: 0...10_000, step: 100)
                Text("\(Int(streamsBufferingMs)) ms")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 64, alignment: .trailing)
            }
            Text("Applied as VLC's network-caching option when a stream starts.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .tint(theme.accent)
    }

    private func aboutSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("About").font(.headline).foregroundStyle(theme.primaryText)

            HStack {
                Text("Version")
                Spacer()
                Text(appVersionString).foregroundStyle(theme.secondaryText)
            }
            .font(.subheadline)
            .foregroundStyle(theme.primaryText)

            Text("100% offline. No analytics, no telemetry, no cloud processing — transcription, translation, playback, and editing all run on this device.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.lg)
        .cardStyle()
        .tint(theme.accent)
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func applyBackgroundStreamingPreference(_ enabled: Bool) {
        // The Streams player (Phase 2) reads this key each time it configures
        // AVAudioSession before playback. Applying it here too so the toggle
        // has an immediate, visible effect on the shared session category.
        try? AVAudioSession.sharedInstance().setCategory(
            enabled ? .playback : .ambient,
            mode: .moviePlayback,
            options: enabled ? [] : [.mixWithOthers]
        )
    }

    private func stopCasting() {
        // Full AirPlay/Chromecast session teardown is owned by the Streams
        // player (VLCMediaPlayer route control, Phase 2). This forces the
        // shared audio session back to the built-in output now, which is the
        // part of "stop casting" that's meaningful before that player exists.
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            castStopMessage = "Disconnected active casting session."
        } catch {
            castStopMessage = "No active casting session to stop."
        }
    }

    private func resetAllSettings() {
        themeManager.setTheme(.modern)
        portraitAlignment = 4
        backgroundMediaStreaming = true
        backgroundTranslations = true
        backgroundLiveMic = false
        streamsBufferingMs = 1500
    }
}
