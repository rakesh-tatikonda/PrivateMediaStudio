import SwiftUI

struct AdjustToolSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        let theme = themeManager.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Adjust").font(.headline).foregroundStyle(theme.primaryText)
                    Spacer()
                    if !viewModel.project.colorGrading.isIdentity {
                        Button("Reset") { viewModel.project.colorGrading = ColorGradingSettings() }
                            .font(.caption)
                    }
                }

                gradingSlider("Brightness", value: $viewModel.project.colorGrading.brightness)
                gradingSlider("Highlights", value: $viewModel.project.colorGrading.highlights)
                gradingSlider("Shadows", value: $viewModel.project.colorGrading.shadows)
                gradingSlider("Whites", value: $viewModel.project.colorGrading.whites)
                gradingSlider("Blacks", value: $viewModel.project.colorGrading.blacks)
                gradingSlider("Saturation", value: $viewModel.project.colorGrading.saturation)
                gradingSlider("Vibrance", value: $viewModel.project.colorGrading.vibrance)
                gradingSlider("Warmth", value: $viewModel.project.colorGrading.warmth)
                gradingSlider("Sharpness", value: $viewModel.project.colorGrading.sharpness)
                gradingSlider("Clarity", value: $viewModel.project.colorGrading.clarity)
                gradingSlider("Vignette", value: $viewModel.project.colorGrading.vignette, range: 0...1)
            }
            .padding(Spacing.lg)
        }
        .tint(theme.accent)
    }

    private func gradingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = -1...1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.primaryText)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
            }
            Slider(value: value, in: range)
        }
    }
}
