import Foundation
import CoreGraphics

/// Individual text recognition result with bounding box
struct OCRResult {
    let text: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized coordinates (0-1)
}

/// OCR result with coordinates normalized relative to the square guide (top-left origin)
struct GuideRelativeOCRResult {
    let original: OCRResult
    let guideRelativeBox: CGRect  // 0-1 within the guide, top-left origin

    var text: String { original.text }
    var confidence: Float { original.confidence }
}

/// Complete parsed table structure from monitor
struct RecognizedTable {
    var workoutType: String?
    var category: WorkoutCategory?
    var date: Date?
    var totalTime: String?
    var averages: TableRow?         // Overall workout averages row
    var rows: [TableRow]
    var averageConfidence: Double

    init(
        workoutType: String? = nil,
        category: WorkoutCategory? = nil,
        date: Date? = nil,
        totalTime: String? = nil,
        averages: TableRow? = nil,
        rows: [TableRow] = [],
        averageConfidence: Double = 0.0
    ) {
        self.workoutType = workoutType
        self.category = category
        self.date = date
        self.totalTime = totalTime
        self.averages = averages
        self.rows = rows
        self.averageConfidence = averageConfidence
    }
}

/// Single row in the workout table
struct TableRow {
    var time: OCRResult?
    var meters: OCRResult?
    var splitPer500m: OCRResult?
    var strokeRate: OCRResult?
    var boundingBox: CGRect  // Entire row bounding box

    init(boundingBox: CGRect = .zero) {
        self.boundingBox = boundingBox
    }
}
