import SwiftUI

/// Overlay showing recognized text with bounding boxes and confidence colors
struct OCROverlayView: View {

    let ocrResults: [OCRResult]
    let screenSize: CGSize

    var body: some View {
        Canvas { context, size in
            for result in ocrResults {
                // Convert Vision coordinates (0-1, bottom-left origin)
                // to SwiftUI coordinates (pixels, top-left origin)
                let rect = convertToSwiftUICoordinates(
                    result.boundingBox,
                    canvasSize: size
                )

                // Draw bounding box
                let color = confidenceColor(for: result.confidence)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 4),
                    with: .color(color),
                    lineWidth: 2
                )

                // Draw text label (optional, might clutter)
                // Uncomment if you want to see the recognized text
                /*
                let textRect = CGRect(
                    x: rect.minX,
                    y: rect.minY - 20,
                    width: rect.width,
                    height: 20
                )
                context.fill(
                    Path(roundedRect: textRect, cornerRadius: 4),
                    with: .color(.black.opacity(0.7))
                )
                */
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helper Methods

    private func convertToSwiftUICoordinates(
        _ visionBox: CGRect,
        canvasSize: CGSize
    ) -> CGRect {
        // Vision uses normalized coordinates (0-1) with bottom-left origin
        // SwiftUI uses pixel coordinates with top-left origin

        let x = visionBox.minX * canvasSize.width
        let width = visionBox.width * canvasSize.width
        let y = (1 - visionBox.maxY) * canvasSize.height  // Flip Y
        let height = visionBox.height * canvasSize.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func confidenceColor(for confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .yellow
        } else {
            return .red
        }
    }
}
