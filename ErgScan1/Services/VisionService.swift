import Foundation
import Vision
import CoreImage
import UIKit

/// Actor for thread-safe OCR processing using Vision framework
actor VisionService {

    // MARK: - Properties

    private let textRecognitionRequest: VNRecognizeTextRequest

    // MARK: - Initialization

    init() {
        // Configure Vision text recognition request
        textRecognitionRequest = VNRecognizeTextRequest()
        textRecognitionRequest.recognitionLevel = .accurate  // Best accuracy for numbers
        textRecognitionRequest.usesLanguageCorrection = false // Disable autocorrect for numbers
        textRecognitionRequest.recognitionLanguages = ["en-US"]
    }

    // MARK: - Public Methods

    /// Recognize text in a pixel buffer (from camera frame)
    /// - Parameter pixelBuffer: CVPixelBuffer from camera
    /// - Returns: Array of OCR results with text, confidence, and bounding boxes
    func recognizeText(in pixelBuffer: CVPixelBuffer) async throws -> [OCRResult] {
        let requestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        try requestHandler.perform([textRecognitionRequest])

        guard let observations = textRecognitionRequest.results else {
            return []
        }

        return observations.compactMap { observation in
            // Get top candidate text
            guard let topCandidate = observation.topCandidates(1).first else {
                return nil
            }

            // Filter low confidence results
            guard topCandidate.confidence > 0.3 else {
                return nil
            }

            return OCRResult(
                text: topCandidate.string,
                confidence: topCandidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    /// Recognize text in a UIImage (for testing with photos)
    /// - Parameter image: UIImage to process
    /// - Returns: Array of OCR results
    func recognizeText(in image: UIImage) async throws -> [OCRResult] {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        let requestHandler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .up,
            options: [:]
        )

        try requestHandler.perform([textRecognitionRequest])

        guard let observations = textRecognitionRequest.results else {
            return []
        }

        return observations.compactMap { observation in
            guard let topCandidate = observation.topCandidates(1).first else {
                return nil
            }

            guard topCandidate.confidence > 0.3 else {
                return nil
            }

            return OCRResult(
                text: topCandidate.string,
                confidence: topCandidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}

// MARK: - Errors

enum VisionError: Error {
    case invalidImage
    case noResults
}
