import Foundation
import CoreGraphics
import AVFoundation

/// The guide's rect in Vision normalized coordinates (bottom-left origin)
struct GuideRegion {
    let visionRect: CGRect
}

/// Maps between Vision full-frame coordinates and guide-relative coordinates
struct GuideCoordinateMapper {

    /// Compute a pixel-space crop rect for the guide within a captured photo.
    /// Uses the preview layer to map screen coordinates to normalized camera coordinates,
    /// then scales to the photo's pixel dimensions.
    static func computeGuideCropRect(
        guideFrameInLayer: CGRect,
        previewLayer: AVCaptureVideoPreviewLayer,
        photoSize: CGSize
    ) -> CGRect {
        // Convert guide frame to normalized metadata coordinates (0-1, top-left origin)
        let normalized = previewLayer.metadataOutputRectConverted(fromLayerRect: guideFrameInLayer)

        // Scale to photo pixel coordinates
        let pixelRect = CGRect(
            x: normalized.origin.x * photoSize.width,
            y: normalized.origin.y * photoSize.height,
            width: normalized.width * photoSize.width,
            height: normalized.height * photoSize.height
        )

        // Clamp to photo bounds
        let photoBounds = CGRect(origin: .zero, size: photoSize)
        return pixelRect.intersection(photoBounds)
    }

    /// Compute the guide's position in Vision coordinate space using the preview layer's built-in conversion.
    static func computeGuideRegion(
        guideFrameInLayer: CGRect,
        previewLayer: AVCaptureVideoPreviewLayer
    ) -> GuideRegion {
        let avfRect = previewLayer.metadataOutputRectConverted(fromLayerRect: guideFrameInLayer)

        // Convert from AVFoundation (top-left origin) to Vision (bottom-left origin)
        let visionRect = CGRect(
            x: avfRect.origin.x,
            y: 1.0 - avfRect.origin.y - avfRect.height,
            width: avfRect.width,
            height: avfRect.height
        )

        return GuideRegion(visionRect: visionRect)
    }

    /// Convert a Vision bounding box to guide-relative coordinates (top-left origin, 0-1 within the square).
    /// Returns nil if the result's center is outside the guide.
    static func visionToGuideRelative(
        _ visionBox: CGRect,
        guideRegion: GuideRegion
    ) -> CGRect? {
        let gr = guideRegion.visionRect
        guard gr.width > 0, gr.height > 0 else { return nil }

        let relX = (visionBox.origin.x - gr.origin.x) / gr.width
        let relY = (visionBox.origin.y - gr.origin.y) / gr.height
        let relW = visionBox.width / gr.width
        let relH = visionBox.height / gr.height

        // Flip Y to top-left origin
        let flippedY = 1.0 - relY - relH

        let result = CGRect(x: relX, y: flippedY, width: relW, height: relH)

        let tolerance: CGFloat = 0.1
        let expandedUnit = CGRect(
            x: -tolerance, y: -tolerance,
            width: 1 + 2 * tolerance, height: 1 + 2 * tolerance
        )
        guard expandedUnit.contains(CGPoint(x: result.midX, y: result.midY)) else {
            return nil
        }

        return result
    }
}
