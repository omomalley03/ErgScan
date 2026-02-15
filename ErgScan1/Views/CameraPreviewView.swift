import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }

    /// Custom UIView that keeps the preview layer frame in sync via layoutSubviews
    class PreviewUIView: UIView {
        private weak var currentPreviewLayer: AVCaptureVideoPreviewLayer?

        func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
            guard layer !== currentPreviewLayer else { return }
            currentPreviewLayer?.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
            currentPreviewLayer = layer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            currentPreviewLayer?.frame = bounds
        }
    }
}
