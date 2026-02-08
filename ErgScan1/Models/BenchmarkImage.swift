import Foundation
import SwiftData

/// Individual captured image with OCR results for benchmark testing
/// Stores raw image data and OCR outputs for accuracy comparison
@Model
final class BenchmarkImage {
    var id: UUID
    var workout: BenchmarkWorkout?
    var capturedDate: Date

    // Image storage (compressed JPEG)
    @Attribute(.externalStorage)
    var imageData: Data

    // Image metadata
    var angleDescription: String?  // e.g., "straight on", "angled left", "zoomed out"
    var resolution: String?  // e.g., "1920x1080"

    // OCR results (raw outputs before ground truth approval)
    var rawOCRResults: Data?  // JSON-encoded [GuideRelativeOCRResult]
    var parsedTable: Data?  // JSON-encoded RecognizedTable
    var ocrConfidence: Double?
    var parserDebugLog: String?  // Verbose parser log for debugging

    // Comparison with ground truth (populated during retesting)
    var accuracyScore: Double?  // Percentage of fields matching ground truth (0.0-1.0)
    var lastTestedDate: Date?

    init(
        id: UUID = UUID(),
        capturedDate: Date = Date(),
        imageData: Data,
        angleDescription: String? = nil,
        resolution: String? = nil,
        rawOCRResults: Data? = nil,
        parsedTable: Data? = nil,
        ocrConfidence: Double? = nil
    ) {
        self.id = id
        self.capturedDate = capturedDate
        self.imageData = imageData
        self.angleDescription = angleDescription
        self.resolution = resolution
        self.rawOCRResults = rawOCRResults
        self.parsedTable = parsedTable
        self.ocrConfidence = ocrConfidence
    }
}
