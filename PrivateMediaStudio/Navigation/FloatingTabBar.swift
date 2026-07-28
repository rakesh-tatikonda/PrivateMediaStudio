import SwiftUI

enum AppTab: Int, CaseIterable {
    case captions, streams, editor, settings

    var title: String {
        switch self {
        case .captions: return "Captions"
        case .streams: return "Streams"
        case .editor: return "Editor"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .captions: return "quote.bubble.fill"
        case .streams: return "video.fill"
        case .editor: return "scissors"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Floating, pill-shaped tab bar anchored to the bottom center. Replaces the
/// system TabView chrome so the design system controls every pixel — spec
/// requires the nav bar to "dynamically adapt to the selected theme".
struct FloatingTabBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selection: AppTab

    var body: some View {
        let theme = themeManager.currentTheme

        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(for: tab, theme: theme)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background {
            Capsule(style: .continuous)
                .fill(theme.surface.map { AnyShapeStyle($0) } ?? AnyShapeStyle(theme.surfaceColor))
        }
        .overlay {
            if theme == .retro {
                Capsule().strokeBorder(theme.accentSecondary.opacity(0.7), lineWidth: 1.5)
            }
        }
        .shadow(color: theme.cardShadow, radius: 16, y: 6)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private func tabButton(for tab: AppTab, theme: AppTheme) -> some View {
        let isSelected = selection == tab

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .retroGlow(isSelected ? theme : .modern, color: theme.accent) // .modern → no-op when not selected
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold, design: theme == .retro ? .monospaced : .rounded))
                }
            }
            .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
            .padding(.horizontal, isSelected ? Spacing.md : Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(theme.accent.opacity(0.14))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}
