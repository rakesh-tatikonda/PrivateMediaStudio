import SwiftUI

struct EditorToolbar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var activeTool: EditorTool?

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.lg) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        activeTool = (activeTool == tool) ? nil : tool
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 20))
                            Text(tool.rawValue)
                                .font(.caption2)
                        }
                        .foregroundStyle(activeTool == tool ? theme.accent : theme.secondaryText)
                        .frame(width: 60)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .background(theme.surfaceColor)
    }
}
