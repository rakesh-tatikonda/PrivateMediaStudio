import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selection: AppTab = .captions

    var body: some View {
        ZStack(alignment: .bottom) {
            themeManager.currentTheme.background
                .ignoresSafeArea()

            Group {
                switch selection {
                case .captions:
                    CaptionsView()
                case .streams:
                    StreamsView()
                case .editor:
                    EditorView()
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Reserve space so scrollable content isn't hidden behind the
                // floating bar on any screen.
                Color.clear.frame(height: 64)
            }

            FloatingTabBar(selection: $selection)

            if themeManager.currentTheme == .retro {
                RetroScanlineOverlay()
            }
        }
        .tint(themeManager.currentTheme.accent)
    }
}
