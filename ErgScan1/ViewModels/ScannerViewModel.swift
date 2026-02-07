import Foundation
import Combine
import SwiftUI
import SwiftData
import AVFoundation

@MainActor
class ScannerViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var capturedImage: UIImage?
    @Published var debugResults: [GuideRelativeOCRResult] = []
    @Published var parsedTable: RecognizedTable?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    // MARK: - Services

    let cameraService = CameraService()
    private let visionService = VisionService()
    private let tableParser = TableParserService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward cameraService changes so the view re-renders
        // when isSessionRunning changes
        cameraService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Camera Setup

    func setupCamera() async {
        do {
            let authorized = await cameraService.requestCameraPermission()
            guard authorized else {
                errorMessage = "Camera permission denied. Please enable in Settings."
                return
            }

            try await cameraService.setupCamera()
            cameraService.startSession()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        cameraService.stopSession()
    }

    // MARK: - Photo Capture & OCR

    func capturePhoto() async {
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        // 1. Capture full-resolution photo
        guard let fullImage = await cameraService.capturePhoto(),
              let fullCG = fullImage.cgImage else {
            errorMessage = "Failed to capture photo."
            return
        }

        // 2. Crop to center square spanning full width of the frame.
        //    Raw CGImage is landscape; the short dimension = screen width.
        let side = min(fullCG.width, fullCG.height)
        let cropRect = CGRect(
            x: (fullCG.width - side) / 2,
            y: (fullCG.height - side) / 2,
            width: side,
            height: side
        )

        guard let croppedCG = fullCG.cropping(to: cropRect) else {
            errorMessage = "Failed to crop photo."
            return
        }
        let croppedImage = UIImage(cgImage: croppedCG, scale: fullImage.scale, orientation: fullImage.imageOrientation)
        capturedImage = croppedImage

        // 4. Run OCR on the cropped image
        do {
            let ocrResults = try await visionService.recognizeText(in: croppedImage)

            // 5. Vision returns bounding boxes in 0-1 relative to the cropped image.
            //    The raw CGImage is landscape (sensor native), so Vision's X = screen Y
            //    and Vision's Y = screen X. Swap axes to get portrait screen coordinates.
            debugResults = ocrResults.map { result in
                let box = result.boundingBox
                let flippedBox = CGRect(
                    x: box.origin.y,
                    y: box.origin.x,
                    width: box.height,
                    height: box.width
                )
                return GuideRelativeOCRResult(
                    original: result,
                    guideRelativeBox: flippedBox
                )
            }

            // Run the parser on the guide-relative results
            parsedTable = tableParser.parseTable(from: debugResults)

        } catch {
            errorMessage = "OCR error: \(error.localizedDescription)"
        }
    }

    // MARK: - Retake

    func retake() {
        capturedImage = nil
        debugResults = []
        parsedTable = nil
    }
}
