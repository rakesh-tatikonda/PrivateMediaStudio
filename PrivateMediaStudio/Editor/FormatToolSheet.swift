import SwiftUI

struct FormatToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel

    @State private var customWidth = "1920"
    @State private var customHeight = "1080"
    @State private var useCustom = false

    private let presets: [EditorResolution] = [.p480, .p720, .p1080, .p4k]

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Output Resolution").font(.headline).foregroundStyle(theme.primaryText)

            ForEach(presets) { preset in
                Button {
                    useCustom = false
                    viewModel.project.resolution = preset
                } label: {
                    HStack {
                        Text(preset.id)
                        Spacer()
                        let (w, h) = preset.dimensions
                        Text("\(w)\u{00D7}\(h)").foregroundStyle(theme.secondaryText)
                        if !useCustom, viewModel.project.resolution == preset {
                            Image(systemName: "checkmark").foregroundStyle(theme.accent)
                        }
                    }
                }
                .foregroundStyle(theme.primaryText)
            }

            Divider()

            Button {
                useCustom = true
                applyCustom()
            } label: {
                HStack {
                    Text("Custom")
                    Spacer()
                    if useCustom { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                }
            }
            .foregroundStyle(theme.primaryText)

            if useCustom {
                HStack {
                    TextField("Width", text: $customWidth)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customWidth) { _, _ in applyCustom() }
                    Text("\u{00D7}").foregroundStyle(theme.secondaryText)
                    TextField("Height", text: $customHeight)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customHeight) { _, _ in applyCustom() }
                }
            }
        }
        .padding(Spacing.lg)
    }

    private func applyCustom() {
        guard let w = Int(customWidth), let h = Int(customHeight), w > 0, h > 0 else { return }
        viewModel.project.resolution = .custom(width: w, height: h)
    }
}
