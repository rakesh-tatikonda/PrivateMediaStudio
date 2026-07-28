import Foundation

/// Central registry of @AppStorage keys. Defined once so Settings (which
/// writes these) and other tabs (which read them, e.g. Captions checking
/// "Background Live Mic" before starting a background-capable session) never
/// drift out of sync via typo'd string literals.
enum AppStorageKeys {
    static let theme = "appTheme"
    static let portraitSubtitleAlignment = "portraitSubtitleAlignment"     // Int 1...7
    static let backgroundMediaStreaming = "backgroundMediaStreaming"       // Bool
    static let backgroundTranslations = "backgroundTranslations"          // Bool
    static let backgroundLiveMic = "backgroundLiveMic"                    // Bool
    static let streamsBufferingMs = "streamsBufferingMs"                  // Int 0...10000
}
