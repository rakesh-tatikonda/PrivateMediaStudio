import SwiftUI

/// Subtle CRT-style scanline overlay, shown only when the Retro theme is
/// active. Applied once at the root (RootTabView) so every screen picks it
/// up automatically rather than each screen needing to remember to add it.
struct RetroScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let lineSpacing: CGFloat = 3
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.black.opacity(0.06))
                    )
                    y += lineSpacing
                }
            }
            .allowsHitTesting(false)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Slow pulsing glow, used sparingly on Retro-theme accent elements (e.g. an
/// active recording indicator) to lean into the "80s/90s UI motif" spec
/// requirement without overdoing it on every screen.
struct RetroGlowPulse: ViewModifier {
    let color: Color
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(pulsing ? 0.9 : 0.4), radius: pulsing ? 10 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension View {
    /// Applies the pulsing glow only when the given theme is `.retro`;
    /// a no-op modifier otherwise so callers don't need an if/else at the
    /// call site.
    @ViewBuilder
    func retroGlow(_ theme: AppTheme, color: Color) -> some View {
        if theme == .retro {
            self.modifier(RetroGlowPulse(color: color))
        } else {
            self
        }
    }
}

/// Segmented "LED meter" progress bar for Retro theme, replacing the plain
/// filled strip used by Modern/Dark. Draws a fixed number of discrete
/// segments (like a hardware VU meter) instead of a continuous fill.
struct RetroLEDProgressBar: View {
    let fraction: Double
    let color: Color
    var segmentCount: Int = 14

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = (geo.size.width - CGFloat(segmentCount - 1) * 2) / CGFloat(segmentCount)
            let litCount = Int((fraction.clamped01) * Double(segmentCount))

            HStack(spacing: 2) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    Rectangle()
                        .fill(index < litCount ? color : color.opacity(0.15))
                        .frame(width: max(1, segmentWidth))
                }
            }
        }
    }
}

private extension Double {
    var clamped01: Double { min(max(self, 0), 1) }
}
