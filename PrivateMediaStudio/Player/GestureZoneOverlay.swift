import SwiftUI
import UIKit

/// Invisible 3-column tap overlay per spec: left 33% rewinds 5s, right 33%
/// forwards 5s, center 33% just absorbs double-taps (so the OS's own
/// double-tap-to-zoom gesture on the underlying video view never fires).
struct GestureZoneOverlay: View {
    let onRewind: () -> Void
    let onForward: () -> Void
    let onToggleControls: () -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                zone(width: geo.size.width / 3) {
                    onRewind()
                    flashFeedback(.left)
                } singleTap: { onToggleControls() }

                zone(width: geo.size.width / 3) {
                    // Center zone: double-tap absorbed, does nothing else.
                } singleTap: { onToggleControls() }

                zone(width: geo.size.width / 3) {
                    onForward()
                    flashFeedback(.right)
                } singleTap: { onToggleControls() }
            }
        }
    }

    private enum FlashSide { case left, right }
    private func flashFeedback(_ side: FlashSide) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func zone(width: CGFloat, doubleTap: @escaping () -> Void, singleTap: @escaping () -> Void) -> some View {
        let doubleTapGesture = TapGesture(count: 2).onEnded(doubleTap)
        let singleTapGesture = TapGesture(count: 1).onEnded(singleTap)

        return Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(doubleTapGesture.exclusively(before: singleTapGesture))
    }
}
