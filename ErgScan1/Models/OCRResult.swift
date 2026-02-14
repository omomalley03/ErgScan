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
    var isVariableInterval: Bool?   // true for variable intervals, nil/false otherwise
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
        isVariableInterval: Bool? = nil,
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
        self.isVariableInterval = isVariableInterval
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

    // MARK: - Data Completeness

    struct CompletenessCheck {
        let isComplete: Bool
        let reason: String?
        let expectedTotal: Int?
        let actualTotal: Int?
    }

    func checkDataCompleteness() -> CompletenessCheck {
        guard let category = category else {
            return CompletenessCheck(isComplete: true, reason: nil, expectedTotal: nil, actualTotal: nil)
        }

        switch category {
        case .interval:
            return checkIntervalCompleteness()
        case .single:
            return checkSingleCompleteness()
        }
    }

    private func checkIntervalCompleteness() -> CompletenessCheck {
        print("🔍 Workout '\(workoutType ?? "unknown")' is Interval type, checking completeness via sum of interval meters")

        // Sum all interval meters
        let actualSum = rows.compactMap { row -> Int? in
            guard let metersText = row.meters?.text else { return nil }
            return Int(metersText)
        }.reduce(0, +)

        // Compare to averages row total
        guard let expectedText = averages?.meters?.text, let expected = Int(expectedText) else {
            return CompletenessCheck(isComplete: true, reason: nil, expectedTotal: nil, actualTotal: nil)
        }

        // Within 1% tolerance
        let tolerance = Double(expected) * 0.01
        let difference = abs(Double(actualSum) - Double(expected))
        let isComplete = difference <= tolerance

        print("   ➜ Sum of intervals: \(actualSum)m, Expected: \(expected)m, Complete: \(isComplete)")

        let reason = isComplete ? nil : "Sum of intervals (\(actualSum)m) doesn't match total (\(expected)m)"
        return CompletenessCheck(isComplete: isComplete, reason: reason, expectedTotal: expected, actualTotal: actualSum)
    }

    private func checkSingleCompleteness() -> CompletenessCheck {
        // Determine if this is a distance-based or time-based single workout
        // Distance-based workouts are ONLY a 3-5 digit number followed by "m" (e.g., "2000m", "5000m")
        // This avoids confusion with variable interval workouts like "3000m / 2000m / 1000m"
        let isDistanceBased: Bool = {
            guard let type = workoutType else { return false }
            // Check if it matches pattern: 3-5 digits followed by "m", nothing else
            let pattern = "^\\d{3,5}m$"
            return type.range(of: pattern, options: .regularExpression) != nil
        }()

        if isDistanceBased {
            print("🔍 Workout '\(workoutType ?? "unknown")' is Single Distance type, checking completeness via last split meter")

            // For distance-based singles (e.g., "2000m"), check last split meter
            guard let lastRow = rows.last else {
                return CompletenessCheck(isComplete: true, reason: nil, expectedTotal: nil, actualTotal: nil)
            }

            if let lastMeters = lastRow.meters?.text, let lastMetersInt = Int(lastMeters),
               let expectedText = averages?.meters?.text, let expected = Int(expectedText) {
                let tolerance = Double(expected) * 0.01
                let difference = abs(Double(lastMetersInt) - Double(expected))
                let isComplete = difference <= tolerance

                print("   ➜ Last split: \(lastMetersInt)m, Expected: \(expected)m, Complete: \(isComplete)")

                let reason = isComplete ? nil : "Last split (\(lastMetersInt)m) doesn't reach total (\(expected)m)"
                return CompletenessCheck(isComplete: isComplete, reason: reason, expectedTotal: expected, actualTotal: lastMetersInt)
            }
        } else {
            // For time-based singles (e.g., "30:00") or anything else (including misclassified intervals), sum all split/interval meters
            print("🔍 Workout '\(workoutType ?? "unknown")' is Single Time (or other) type, checking completeness via sum of split/interval meters")

            let actualSum = rows.compactMap { row -> Int? in
                guard let metersText = row.meters?.text else { return nil }
                return Int(metersText)
            }.reduce(0, +)

            // Compare to averages row total
            if let expectedText = averages?.meters?.text, let expected = Int(expectedText) {
                let tolerance = Double(expected) * 0.01
                let difference = abs(Double(actualSum) - Double(expected))
                let isComplete = difference <= tolerance

                print("   ➜ Sum of splits/intervals: \(actualSum)m, Expected: \(expected)m, Complete: \(isComplete)")

                let reason = isComplete ? nil : "Sum of splits (\(actualSum)m) doesn't match total (\(expected)m)"
                return CompletenessCheck(isComplete: isComplete, reason: reason, expectedTotal: expected, actualTotal: actualSum)
            }
        }

        return CompletenessCheck(isComplete: true, reason: nil, expectedTotal: nil, actualTotal: nil)
    }

    private func approximateSeconds(_ timeStr: String) -> Double {
        let parts = timeStr.replacingOccurrences(of: ".", with: ":").split(separator: ":")
        var seconds = 0.0
        for (i, part) in parts.reversed().enumerated() {
            if let val = Double(part) {
                switch i {
                case 0: seconds += val
                case 1: seconds += val * 60
                case 2: seconds += val * 3600
                case 3: seconds += val * 3600
                default: break
                }
            }
        }
        return seconds
    }
}

// MARK: - Codable Conformance

extension OCRResult: Codable {}
extension GuideRelativeOCRResult: Codable {}
extension RecognizedTable: Codable {}
extension TableRow: Codable {}
