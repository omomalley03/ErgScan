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
    var description: String?        // Raw descriptor string, e.g. "3x20:00/1:15r"
    var reps: Int?                  // Interval count (nil for single)
    var workPerRep: String?         // "20:00" or "1000m" (nil for single)
    var restPerRep: String?         // "1:15" (nil for single)
    var totalDistance: Int?          // Total meters
    var averages: TableRow?         // Overall workout averages/summary row
    var rows: [TableRow]            // Interval results or split results
    var averageConfidence: Double

    init(
        workoutType: String? = nil,
        category: WorkoutCategory? = nil,
        date: Date? = nil,
        totalTime: String? = nil,
        description: String? = nil,
        reps: Int? = nil,
        workPerRep: String? = nil,
        restPerRep: String? = nil,
        totalDistance: Int? = nil,
        averages: TableRow? = nil,
        rows: [TableRow] = [],
        averageConfidence: Double = 0.0
    ) {
        self.workoutType = workoutType
        self.category = category
        self.date = date
        self.totalTime = totalTime
        self.description = description
        self.reps = reps
        self.workPerRep = workPerRep
        self.restPerRep = restPerRep
        self.totalDistance = totalDistance
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
    var heartRate: OCRResult?
    var boundingBox: CGRect  // Entire row bounding box

    init(boundingBox: CGRect = .zero) {
        self.boundingBox = boundingBox
    }
}

// MARK: - Completeness Detection

extension RecognizedTable {
    /// Whether the workout data meets the minimum threshold for locking (70%+ AND workoutType identified)
    var isComplete: Bool {
        // Must have workout type identified to lock
        guard workoutType != nil else { return false }
        return completenessScore >= 0.7
    }

    /// Completeness score from 0.0 to 1.0 based on which fields are present
    var completenessScore: Double {
        var score = 0.0
        var maxScore = 0.0

        // Metadata (30 points)
        maxScore += 30
        if workoutType != nil { score += 10 }
        if description != nil { score += 10 }
        if date != nil { score += 10 }

        // Averages row (40 points)
        maxScore += 40
        if let avg = averages {
            if avg.time != nil { score += 10 }
            if avg.meters != nil { score += 10 }
            if avg.splitPer500m != nil { score += 10 }
            if avg.strokeRate != nil { score += 10 }
        }

        // Data rows (20 points)
        maxScore += 20
        if !rows.isEmpty { score += 20 }

        // Confidence (10 points)
        maxScore += 10
        score += averageConfidence * 10

        return score / maxScore
    }

    /// Hash of essential fields for stability detection
    /// Only includes key fields to avoid minor confidence fluctuations triggering changes
    var stableHash: Int {
        var hasher = Hasher()

        // Hash workout type
        hasher.combine(workoutType)

        // Hash averages key fields
        if let avg = averages {
            hasher.combine(avg.time?.text)
            hasher.combine(avg.meters?.text)
        }

        // Hash row count (not individual row values to avoid confidence fluctuations)
        hasher.combine(rows.count)

        return hasher.finalize()
    }
}

// MARK: - Codable Conformance

extension OCRResult: Codable {}
extension GuideRelativeOCRResult: Codable {}
extension RecognizedTable: Codable {}
extension TableRow: Codable {}
