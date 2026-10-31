import AVFoundation
import SwiftUI

/// SwiftUI has no camera view, so wrap a UIKit view whose backing layer is the
/// live camera preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe: layerClass above guarantees the layer's type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
