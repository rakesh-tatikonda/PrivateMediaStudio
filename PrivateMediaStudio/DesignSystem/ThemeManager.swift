import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case modern   // Theme 1: bright, frosted glass
    case dark     // Theme 2: OLED true black, bright blue accent
    case retro    // Theme 3: nostalgic 80s/90s palette

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modern: return "Modern / Clean"
        case .dark: return "Dark"
        case .retro: return "Retro"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .modern: return .light
        case .dark: return .dark
        case .retro: return .dark
        }
    }

    // MARK: Palette

    var background: Color {
        switch self {
        case .modern: return Color(white: 0.98)
        case .dark: return .black
        case .retro: return Color(red: 0.11, green: 0.08, blue: 0.16)
        }
    }

    var surface: Material? {
        switch self {
        case .modern: return .ultraThinMaterial
        case .dark: return nil
        case .retro: return nil
        }
    }

    var surfaceColor: Color {
        switch self {
        case .modern: return .white.opacity(0.7)
        case .dark: return Color(white: 0.08)
        case .retro: return Color(red: 0.2, green: 0.13, blue: 0.28)
        }
    }

    var accent: Color {
        switch self {
        case .modern: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .dark: return Color(red: 0.1, green: 0.6, blue: 1.0)
        case .retro: return Color(red: 1.0, green: 0.35, blue: 0.6)
        }
    }

    var accentSecondary: Color {
        switch self {
        case .modern: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .dark: return Color(red: 0.4, green: 0.85, blue: 1.0)
        case .retro: return Color(red: 0.4, green: 0.9, blue: 0.85) // cyan/teal 80s accent
        }
    }

    var primaryText: Color {
        switch self {
        case .modern: return .black
        case .dark: return .white
        case .retro: return Color(red: 0.95, green: 0.9, blue: 1.0)
        }
    }

    var secondaryText: Color {
        switch self {
        case .modern: return .black.opacity(0.55)
        case .dark: return .white.opacity(0.6)
        case .retro: return Color(red: 0.95, green: 0.9, blue: 1.0).opacity(0.6)
        }
    }

    var cardShadow: Color {
        switch self {
        case .modern: return .black.opacity(0.08)
        case .dark: return .clear
        case .retro: return accentSecondary.opacity(0.35) // neon glow instead of shadow
        }
    }

    var titleFont: Font {
        switch self {
        case .retro: return .system(.title2, design: .monospaced).weight(.bold)
        default: return .system(.title2, design: .rounded).weight(.bold)
        }
    }

    var bodyFont: Font {
        switch self {
        case .retro: return .system(.body, design: .monospaced)
        default: return .system(.body, design: .default)
        }
    }
}

/// Drives app-wide theme state. Backed by @AppStorage so the choice persists
/// across launches; published so every view using @EnvironmentObject re-renders
/// immediately on change (Settings tab writes to this).
@MainActor
final class ThemeManager: ObservableObject {
    @AppStorage("appTheme") private var storedTheme: String = AppTheme.modern.rawValue

    @Published var currentTheme: AppTheme = .modern

    init() {
        currentTheme = AppTheme(rawValue: storedTheme) ?? .modern
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        storedTheme = theme.rawValue
    }
}
