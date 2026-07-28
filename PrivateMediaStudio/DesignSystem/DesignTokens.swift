import SwiftUI

/// Central spacing/sizing scale. Every screen should pull from here rather than
/// hardcoding padding values, so the app reads as one cohesive system rather
/// than a collection of independently-styled screens.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let card: CGFloat = 20
    static let control: CGFloat = 14
    static let pill: CGFloat = 999
}

/// Reusable "card" surface — respects the active theme's material/opaque choice.
struct CardBackground: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager

    func body(content: Content) -> some View {
        let theme = themeManager.currentTheme
        content
            .background {
                if let material = theme.surface {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(material)
                } else {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(theme.surfaceColor)
                }
            }
            .overlay {
                if theme == .retro {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(theme.accentSecondary.opacity(0.6), lineWidth: 1)
                }
            }
            .shadow(color: theme.cardShadow, radius: theme == .retro ? 12 : 10, y: theme == .retro ? 0 : 4)
    }
}

/// Primary filled button style, themed.
struct PrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject var themeManager: ThemeManager
    var fullWidth: Bool = true
    var colorOverride: Color?

    func makeBody(configuration: Configuration) -> some View {
        let theme = themeManager.currentTheme
        let base = colorOverride ?? theme.accent
        configuration.label
            .font(theme.bodyFont.weight(.semibold))
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(base.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                if theme == .retro {
                    // Chunky raised-button bevel: light edge top-left, dark
                    // edge bottom-right — classic 80s/90s UI motif.
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .black.opacity(0.4)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: configuration.isPressed ? 1 : 2.5
                        )
                }
            }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}
