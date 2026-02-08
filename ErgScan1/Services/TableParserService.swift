import Foundation
import CoreGraphics

/// Parses OCR results from a Concept2 PM5 monitor into structured workout data.
///
/// Pipeline (Steps 0–9):
/// 0. Normalize text (context-aware character substitutions)
/// 1. Find landmark labels (fuzzy matching)
/// 2. Establish column X-anchors from header landmarks
/// 3. Group into rows by Y proximity
/// 4. Extract workout type
/// 5. Extract date
/// 6. Extract total time
/// 7. Extract data rows using column X-anchors
/// 8. Assemble result
/// 9. Filter junk
class TableParserService {

    private let matcher = TextPatternMatcher()
    private let boxAnalyzer = BoundingBoxAnalyzer()

    /// Column X-anchor tolerance: a value belongs to a column if within ±0.05
    private let columnTolerance: CGFloat = 0.05

    /// Debug log buffer
    private var debugLog: [String] = []

    // MARK: - Working Types

    /// Normalized OCR result with original spatial data preserved
    private struct NormalizedResult {
        let originalText: String
        let normalizedText: String
        let confidence: Float
        let midX: CGFloat
        let midY: CGFloat
        let box: CGRect
        let guideRelativeResult: GuideRelativeOCRResult
    }

    /// Detected landmark with its position
    private struct DetectedLandmark {
        let type: TextPatternMatcher.Landmark
        let midX: CGFloat
        let midY: CGFloat
    }

    /// Column X-anchors derived from header landmarks
    private struct ColumnAnchors {
        var timeX: CGFloat?
        var metersX: CGFloat?
        var splitX: CGFloat?
        var rateX: CGFloat?
        var headerY: CGFloat?
    }

    // MARK: - Public API

    func parseTable(from results: [GuideRelativeOCRResult]) -> (table: RecognizedTable, debugLog: String) {
        debugLog = []
        var table = RecognizedTable()

        guard !results.isEmpty else {
            log("⚠️ No OCR results to parse")
            return (table, debugLog.joined(separator: "\n"))
        }

        log("🚀 Starting parser with \(results.count) OCR results")

        // Step 0: Normalize all text
        let normalized = results.map { result -> NormalizedResult in
            NormalizedResult(
                originalText: result.text,
                normalizedText: matcher.normalize(result.text),
                confidence: result.confidence,
                midX: result.guideRelativeBox.midX,
                midY: result.guideRelativeBox.midY,
                box: result.guideRelativeBox,
                guideRelativeResult: result
            )
        }

        log("\n📝 Step 0: Normalize text")
        for n in normalized {
            if n.originalText != n.normalizedText {
                log("  \"\(n.originalText)\" → \"\(n.normalizedText)\" at X=\(String(format: "%.2f", n.midX)) Y=\(String(format: "%.2f", n.midY))")
            }
        }
        log("  ✓ Normalized \(normalized.count) results")

        // Step 1: Find landmarks
        let landmarks = findLandmarks(normalized)

        log("\n🔍 Step 1: Find landmarks")
        if landmarks.isEmpty {
            log("  ⚠️ No landmarks found")
        } else {
            for lm in landmarks {
                log("  • \(lm.type) at X=\(String(format: "%.2f", lm.midX)) Y=\(String(format: "%.2f", lm.midY))")
            }
        }

        // Step 2: Establish column X-anchors
        let anchors = establishColumnAnchors(landmarks)

        log("\n⚓️ Step 2: Establish column X-anchors")
        log("  timeX = \(anchors.timeX.map { String(format: "%.2f", $0) } ?? "nil")")
        log("  metersX = \(anchors.metersX.map { String(format: "%.2f", $0) } ?? "nil")")
        log("  splitX = \(anchors.splitX.map { String(format: "%.2f", $0) } ?? "nil")")
        log("  rateX = \(anchors.rateX.map { String(format: "%.2f", $0) } ?? "nil")")
        log("  headerY = \(anchors.headerY.map { String(format: "%.2f", $0) } ?? "nil")")

        // Step 3: Group into rows
        let rows = boxAnalyzer.groupIntoRows(results)

        log("\n📋 Step 3: Group into rows")
        log("  Found \(rows.count) rows")
        for (i, row) in rows.enumerated().prefix(10) {
            let texts = row.map { "\"\($0.text)\"" }.joined(separator: ", ")
            log("  Row \(i) (Y≈\(String(format: "%.2f", row.first?.guideRelativeBox.midY ?? 0))): \(texts)")
        }
        if rows.count > 10 {
            log("  ... (\(rows.count - 10) more rows)")
        }

        // Step 4: Extract workout type
        log("\n💪 Step 4: Extract workout type")
        table.workoutType = extractWorkoutType(from: normalized, landmarks: landmarks)
        if let wt = table.workoutType {
            log("  ✓ Found: \"\(wt)\"")
        } else {
            log("  ⚠️ Not found")
        }

        // Step 5: Extract date
        log("\n📅 Step 5: Extract date")
        table.date = extractDate(from: normalized, rows: rows)
        if let date = table.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM dd yyyy"
            log("  ✓ Found: \(formatter.string(from: date))")
        } else {
            log("  ⚠️ Not found")
        }

        // Step 6: Extract total time
        log("\n⏱️ Step 6: Extract total time")
        table.totalTime = extractTotalTime(from: normalized, landmarks: landmarks)
        if let tt = table.totalTime {
            log("  ✓ Found: \"\(tt)\"")
        } else {
            log("  ⚠️ Not found")
        }

        // Step 7 & 9: Extract data rows (skipping junk), assign to columns
        log("\n🔢 Step 7: Extract data rows")
        let headerY = anchors.headerY ?? 0.0
        log("  Header Y threshold: \(String(format: "%.2f", headerY))")
        var dataRows: [TableRow] = []

        for row in rows {
            guard let firstY = row.first?.guideRelativeBox.midY else { continue }
            // Only process rows below the header
            guard firstY > headerY + 0.02 else { continue }

            if let tableRow = extractDataRow(from: row, anchors: anchors) {
                dataRows.append(tableRow)
            }
        }
        log("  ✓ Extracted \(dataRows.count) valid data rows")

        // Step 8: Assemble — first data row = averages, rest = intervals
        log("\n🏗️ Step 8: Assemble result")
        if let first = dataRows.first {
            table.averages = first
            table.rows = Array(dataRows.dropFirst())
            log("  ✓ Averages row assigned")
            log("  ✓ \(table.rows.count) interval rows assigned")
        } else {
            log("  ⚠️ No data rows found")
        }

        // Detect category
        if let workoutType = table.workoutType {
            table.category = matcher.detectWorkoutCategory(workoutType)
        }

        // Calculate confidence
        table.averageConfidence = calculateAverageConfidence(table)

        log("\n✅ Parsing complete")
        log("  Confidence: \(String(format: "%.0f%%", table.averageConfidence * 100))")

        return (table, debugLog.joined(separator: "\n"))
    }

    // MARK: - Debug Logging

    private func log(_ message: String) {
        debugLog.append(message)
    }

    // MARK: - Step 1: Find Landmarks

    private func findLandmarks(_ results: [NormalizedResult]) -> [DetectedLandmark] {
        var landmarks: [DetectedLandmark] = []

        for result in results {
            // Try original text first, then normalized
            if let lm = matcher.matchLandmark(result.originalText) {
                landmarks.append(DetectedLandmark(type: lm, midX: result.midX, midY: result.midY))
            } else if let lm = matcher.matchLandmark(result.normalizedText) {
                landmarks.append(DetectedLandmark(type: lm, midX: result.midX, midY: result.midY))
            }
        }

        // Filter split500m landmarks: only keep those on same Y-level as time/meter headers
        // AND to the right of the meter landmark
        let headerLandmarks = landmarks.filter { $0.type == .time || $0.type == .meter }
        if !headerLandmarks.isEmpty {
            let avgHeaderY = headerLandmarks.map { $0.midY }.reduce(0, +) / CGFloat(headerLandmarks.count)
            let meterLandmark = landmarks.first { $0.type == .meter }

            landmarks = landmarks.filter { lm in
                if lm.type == .split500m {
                    // Check Y-level: must be on same row as headers (±0.03)
                    let onHeaderRow = abs(lm.midY - avgHeaderY) < 0.03
                    // Check X-position: must be at least 0.05 to the right of meter landmark
                    let rightOfMeter = meterLandmark.map { lm.midX > $0.midX + 0.05 } ?? true
                    return onHeaderRow && rightOfMeter
                }
                return true
            }
        }

        return landmarks
    }

    // MARK: - Step 2: Establish Column Anchors

    private func establishColumnAnchors(_ landmarks: [DetectedLandmark]) -> ColumnAnchors {
        var anchors = ColumnAnchors()

        var headerCandidateYs: [CGFloat] = []

        for lm in landmarks {
            switch lm.type {
            case .time:
                anchors.timeX = lm.midX
                headerCandidateYs.append(lm.midY)
            case .meter:
                anchors.metersX = lm.midX
                headerCandidateYs.append(lm.midY)
            case .split500m:
                anchors.splitX = lm.midX
                headerCandidateYs.append(lm.midY)
            case .strokeRateHeader:
                anchors.rateX = lm.midX
                headerCandidateYs.append(lm.midY)
            default:
                break
            }
        }

        // Header Y = average Y of all header landmarks
        if !headerCandidateYs.isEmpty {
            anchors.headerY = headerCandidateYs.reduce(0, +) / CGFloat(headerCandidateYs.count)
        }

        // Fallback: if no rate header found, try Total Time X + 0.02
        if anchors.rateX == nil {
            if let totalTimeLM = landmarks.first(where: { $0.type == .totalTime }) {
                anchors.rateX = totalTimeLM.midX + 0.02
            } else {
                // Final fallback: use rightmost known header + offset, or 0.75
                let knownXs = [anchors.timeX, anchors.metersX, anchors.splitX].compactMap { $0 }
                if let maxX = knownXs.max() {
                    anchors.rateX = min(maxX + 0.09, 0.90)
                } 
            }
        }

        return anchors
    }

    // MARK: - Step 4: Extract Workout Type

    private func extractWorkoutType(
        from results: [NormalizedResult],
        landmarks: [DetectedLandmark]
    ) -> String? {
        // Find "View Detail" landmark
        let viewDetailLM = landmarks.first { $0.type == .viewDetail }

        if let vdY = viewDetailLM?.midY, let vdX = viewDetailLM?.midX {
            // Look for text just below View Detail (Y+0.01 to Y+0.09) and within X ±0.1
            let candidates = results.filter { r in
                r.midY > vdY + 0.01 && r.midY < vdY + 0.09 &&
                abs(r.midX - vdX) < 0.1
            }
            for candidate in candidates {
                let text = candidate.normalizedText
                // Normalize comma in workout type: "3x4:00,3:00r" → "3x4:00/3:00r"
                let fixed = text.replacingOccurrences(of: ",", with: "/")
                if matcher.matchWorkoutType(fixed) { return fixed }
                if matcher.matchWorkoutType(text) { return text }
            }
        }

        // Fallback: scan all results for workout type pattern
        for result in results {
            let text = result.normalizedText
            let fixed = text.replacingOccurrences(of: ",", with: "/")
            if matcher.matchWorkoutType(fixed) { return fixed }
            if matcher.matchWorkoutType(text) { return text }
        }

        return nil
    }

    // MARK: - Step 5: Extract Date

    private func extractDate(
        from results: [NormalizedResult],
        rows: [[GuideRelativeOCRResult]]
    ) -> Date? {
        // Try each result's original text (dates shouldn't be normalized)
        for result in results {
            if let date = matcher.matchDate(result.originalText) { return date }
        }

        // Try combining adjacent results on the same row
        for row in rows {
            let combined = row
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            if let date = matcher.matchDate(combined) { return date }
        }

        return nil
    }

    // MARK: - Step 6: Extract Total Time

    private func extractTotalTime(
        from results: [NormalizedResult],
        landmarks: [DetectedLandmark]
    ) -> String? {
        let totalTimeLM = landmarks.first { $0.type == .totalTime }

        if let lm = totalTimeLM {
            let ttY = lm.midY
            let ttX = lm.midX

            // Look for time value on same Y-level (±0.03) and to the right
            let sameRow = results.filter { r in
                abs(r.midY - ttY) < 0.03 && r.midX > ttX + 0.05
            }
            for candidate in sameRow {
                if matcher.matchTotalTime(candidate.normalizedText) {
                    return candidate.normalizedText
                }
            }

            // Or next Y-level (0.03–0.06 below)
            let nextRow = results.filter { r in
                r.midY > ttY + 0.03 && r.midY < ttY + 0.06
            }
            for candidate in nextRow {
                if matcher.matchTotalTime(candidate.normalizedText) {
                    return candidate.normalizedText
                }
            }
        }

        return nil
    }

    // MARK: - Step 7: Extract Data Row

    private func extractDataRow(
        from row: [GuideRelativeOCRResult],
        anchors: ColumnAnchors
    ) -> TableRow? {
        var tableRow = TableRow()

        // Track bounding box
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = 0

        var hasData = 0

        for result in row {
            let normalized = matcher.normalize(result.text)
            let midX = result.guideRelativeBox.midX
            let box = result.guideRelativeBox

            // Update row bounding box
            minX = min(minX, box.minX)
            maxX = max(maxX, box.maxX)
            minY = min(minY, box.minY)
            maxY = max(maxY, box.maxY)

            // Skip junk
            if matcher.isJunk(result.text) || matcher.isJunk(normalized) { continue }

            // Check for combined split+rate
            if let combined = matcher.parseCombinedSplitRate(normalized) {
                if tableRow.splitPer500m == nil {
                    tableRow.splitPer500m = OCRResult(
                        text: combined.split,
                        confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }
                if tableRow.strokeRate == nil {
                    tableRow.strokeRate = OCRResult(
                        text: combined.rate,
                        confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }
                continue
            }

            // Assign to column by X-anchor proximity
            let column = classifyColumn(midX: midX, anchors: anchors)

            switch column {
            case .time:
                if tableRow.time == nil && (matcher.matchTime(normalized) || matcher.matchSplit(normalized)) {
                    tableRow.time = OCRResult(
                        text: normalized, confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }

            case .meters:
                if tableRow.meters == nil && matcher.matchMeters(normalized) {
                    tableRow.meters = OCRResult(
                        text: normalized, confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }

            case .split:
                if tableRow.splitPer500m == nil && (matcher.matchSplit(normalized) || matcher.matchTime(normalized)) {
                    tableRow.splitPer500m = OCRResult(
                        text: normalized, confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }

            case .rate:
                if tableRow.strokeRate == nil && matcher.matchRate(normalized) {
                    tableRow.strokeRate = OCRResult(
                        text: normalized, confidence: result.confidence,
                        boundingBox: result.original.boundingBox
                    )
                    hasData += 1
                }

            case .unknown:
                // Try pattern-based fallback when no column anchors matched
                assignByPattern(
                    normalized: normalized, result: result,
                    into: &tableRow, hasData: &hasData, anchors: anchors
                )
            }
        }

        tableRow.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Require at least 2 populated fields
        return hasData >= 2 ? tableRow : nil
    }

    // MARK: - Column Classification

    private enum Column {
        case time, meters, split, rate, unknown
    }

    private func classifyColumn(midX: CGFloat, anchors: ColumnAnchors) -> Column {
        var bestColumn: Column = .unknown
        var bestDistance: CGFloat = columnTolerance

        if let tx = anchors.timeX, abs(midX - tx) < bestDistance {
            bestDistance = abs(midX - tx)
            bestColumn = .time
        }
        if let mx = anchors.metersX, abs(midX - mx) < bestDistance {
            bestDistance = abs(midX - mx)
            bestColumn = .meters
        }
        if let sx = anchors.splitX, abs(midX - sx) < bestDistance {
            bestDistance = abs(midX - sx)
            bestColumn = .split
        }
        if let rx = anchors.rateX, abs(midX - rx) < bestDistance {
            bestDistance = abs(midX - rx)
            bestColumn = .rate
        }

        return bestColumn
    }

    /// Fallback: assign by pattern when column anchors don't match
    private func assignByPattern(
        normalized: String,
        result: GuideRelativeOCRResult,
        into row: inout TableRow,
        hasData: inout Int,
        anchors: ColumnAnchors
    ) {
        let ocr = OCRResult(
            text: normalized, confidence: result.confidence,
            boundingBox: result.original.boundingBox
        )

        if row.meters == nil && matcher.matchMeters(normalized) {
            row.meters = ocr
            hasData += 1
        } else if row.strokeRate == nil && matcher.matchRate(normalized) {
            row.strokeRate = ocr
            hasData += 1
        } else if matcher.matchTime(normalized) || matcher.matchSplit(normalized) {
            // Disambiguate time vs split by X position relative to anchors
            let midX = result.guideRelativeBox.midX
            let timeX = anchors.timeX ?? 0.2
            let splitX = anchors.splitX ?? 0.6
            let distToTime = abs(midX - timeX)
            let distToSplit = abs(midX - splitX)

            if distToTime < distToSplit && row.time == nil {
                row.time = ocr
                hasData += 1
            } else if row.splitPer500m == nil {
                row.splitPer500m = ocr
                hasData += 1
            }
        }
    }

    // MARK: - Confidence Calculation

    private func calculateAverageConfidence(_ table: RecognizedTable) -> Double {
        var allRows = table.rows
        if let avg = table.averages { allRows.append(avg) }

        var confidenceSum = 0.0
        var count = 0

        for row in allRows {
            if let time = row.time {
                confidenceSum += Double(time.confidence)
                count += 1
            }
            if let meters = row.meters {
                confidenceSum += Double(meters.confidence)
                count += 1
            }
            if let split = row.splitPer500m {
                confidenceSum += Double(split.confidence)
                count += 1
            }
            if let rate = row.strokeRate {
                confidenceSum += Double(rate.confidence)
                count += 1
            }
        }

        return count > 0 ? confidenceSum / Double(count) : 0.0
    }
}
