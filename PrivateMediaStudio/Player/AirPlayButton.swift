import SwiftUI
import AVKit
import UIKit

/// Wraps the system AVRoutePickerView — the real, standard way to present
/// the AirPlay/Cast picker on iOS. Note: this reliably routes *audio* output
/// (which is how VLCMediaPlayer's sound reaches an AirPlay speaker/TV, since
/// audio goes through the shared AVAudioSession either way). True independent
/// AirPlay *video* streaming the way AVPlayer gets for free is not something
/// VLCKit's public UIView-drawable API exposes directly — matching AVPlayer's
/// video AirPlay behavior would need a secondary encode/output pipeline,
/// which is out of scope for this pass. Screen mirroring (the user's whole
/// display, including this view) still works regardless, via iOS itself.
struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tintColor
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}
