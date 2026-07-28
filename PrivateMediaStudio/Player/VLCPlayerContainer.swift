import SwiftUI
import UIKit
import MobileVLCKit

/// Hosts a VLCMediaPlayer (single item) or VLCMediaListPlayer (playlist
/// queueing, per spec) inside a plain UIViewController whose view is the
/// VLC drawable. PlayerViewModel owns the actual VLCMediaPlayer instance so
/// SwiftUI controls (buttons, sliders) can drive it directly without going
/// through Representable update cycles for every interaction.
struct VLCPlayerContainer: UIViewControllerRepresentable {
    @ObservedObject var playerViewModel: PlayerViewModel

    func makeUIViewController(context: Context) -> VLCDrawableViewController {
        let controller = VLCDrawableViewController()
        playerViewModel.attachDrawable(controller.videoView)
        return controller
    }

    func updateUIViewController(_ uiViewController: VLCDrawableViewController, context: Context) {
        // Nothing to push per-update — PlayerViewModel talks to VLCMediaPlayer directly.
    }
}

final class VLCDrawableViewController: UIViewController {
    let videoView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
