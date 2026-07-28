import SwiftUI

struct SubtitleOverlayView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let text: String?
    let isLandscape: Bool

    @AppStorage(AppStorageKeys.portraitSubtitleAlignment) private var portraitAlignment: Int = 4

    var body: some View {
        VStack {
            if isLandscape {
                // Spec: "strictly snap to 0 in Landscape Mode" — 0 reads as
                // "no custom offset", i.e. the standard bottom-anchored position.
                Spacer()
                subtitleLabel
                    .padding(.bottom, Spacing.lg)
            } else {
                verticalSpacerStack
            }
        }
        .animation(.easeInOut(duration: 0.15), value: text)
    }

    /// Alignment presets 1...7 map to 7 evenly-spaced vertical slots from
    /// near-top (1) to bottom (7): the label sits at a fractional offset of
    /// the available height, computed directly rather than via Spacer
    /// weighting (which only affects compression priority, not proportional
    /// space distribution).
    @ViewBuilder
    private var verticalSpacerStack: some View {
        GeometryReader { geo in
            let slot = max(1, min(7, portraitAlignment))
            let fraction = CGFloat(slot - 1) / 6.0 // 0 (top) ... 1 (bottom)
            let usableHeight = geo.size.height * 0.82 // keep clear of safe areas
            let topOffset = usableHeight * fraction

            subtitleLabel
                .frame(maxWidth: .infinity)
                .position(x: geo.size.width / 2, y: topOffset + Spacing.xl)
        }
    }

    @ViewBuilder
    private var subtitleLabel: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, Spacing.xl)
                .transition(.opacity)
        }
    }
}
