import SwiftUI
import UIKit
import SceneKit

/// Renders 360° video by wrapping the live VLC drawable as a texture on the
/// inside of a sphere, with the camera at the center — pan to look around.
///
/// Honest limitation: MobileVLCKit's public Swift API renders directly into a
/// UIView (`drawable`) and doesn't expose raw decoded frames/textures the way
/// a custom libvlc build with video callbacks would. So this works by
/// snapshotting that UIView every frame via CADisplayLink and re-uploading it
/// as the sphere's texture — it works, and is a known technique, but it's
/// CPU-bound (a UIView render pass per frame) rather than a zero-copy GPU
/// path, so expect this to run hotter/lower-fps than a purpose-built 360
/// player. A production-quality version would swap this for a custom VLC
/// build exposing `libvlc_video_set_callbacks` for direct GPU texture upload.
struct VRSphereView: UIViewRepresentable {
    let sourceView: UIView

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false

        let scene = SCNScene()
        scnView.scene = scene

        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 48
        sphere.firstMaterial?.isDoubleSided = true
        sphere.firstMaterial?.diffuse.contents = UIColor.black

        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.scale = SCNVector3(-1, 1, 1) // invert so texture renders on the inside
        scene.rootNode.addChildNode(sphereNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 90
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)

        context.coordinator.sphereNode = sphereNode
        context.coordinator.cameraNode = cameraNode
        context.coordinator.sourceView = sourceView
        context.coordinator.startCapturing()

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.sourceView = sourceView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var sphereNode: SCNNode?
        weak var cameraNode: SCNNode?
        weak var sourceView: UIView?
        private var displayLink: CADisplayLink?
        private var yaw: Float = 0
        private var pitch: Float = 0

        func startCapturing() {
            let link = CADisplayLink(target: self, selector: #selector(captureFrame))
            // Snapshotting a live UIView every single frame is expensive;
            // 15fps texture refresh is a pragmatic middle ground for a
            // "look around a 360 scene" experience on top of this technique.
            link.preferredFramesPerSecond = 15
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func captureFrame() {
            guard let sourceView, sourceView.bounds.width > 0, sourceView.bounds.height > 0 else { return }
            let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
            let image = renderer.image { _ in
                sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
            }
            sphereNode?.geometry?.firstMaterial?.diffuse.contents = image
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            yaw -= Float(translation.x) * 0.005
            pitch = max(-1.4, min(1.4, pitch - Float(translation.y) * 0.005))
            cameraNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
            gesture.setTranslation(.zero, in: view)
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
