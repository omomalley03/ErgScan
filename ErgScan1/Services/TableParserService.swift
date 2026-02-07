import Foundation
import CoreGraphics

/// Service for parsing OCR results into structured workout data.
/// Uses pattern-first classification: reads all text, groups into rows,
/// then identifies each row's role and content by regex patterns.
class TableParserService {

    // MARK: - Properties

    private let boxAnalyzer = BoundingBoxAnalyzer()
    private let patternMatcher = TextPatternMatcher()
    private let rowClassifier = RowClassifier()

    // MARK: - Public Methods

    func parseTable(from ocrResults: [OCRResult], guideRegion: GuideRegion) -> RecognizedTable {
        var table = RecognizedTable()

        // Step 1: Convert all results to guide-relative coordinates, discard anything outside
        let guideResults = ocrResults.compactMap { result -> GuideRelativeOCRResult? in
            guard let relBox = GuideCoordinateMapper.visionToGuideRelative(
                result.boundingBox,
                guideRegion: guideRegion
            ) else { return nil }
            return GuideRelativeOCRResult(original: result, guideRelativeBox: relBox)
        }

        // Step 2: Group ALL results into rows by Y proximity (no zone filtering)
        let allRows = boxAnalyzer.groupIntoRows(guideResults)

        // Step 3: Classify every row by pattern matching
        let classifiedRows = rowClassifier.classifyRows(allRows)

        #if DEBUG
        print("=== OCR Debug ===")
        print("Total OCR results: \(ocrResults.count)")
        print("Guide-relative results: \(guideResults.count)")
        print("Rows found: \(allRows.count)")
        for (i, classified) in classifiedRows.enumerated() {
            let texts = classified.results.map { "'\($0.text)'" }.joined(separator: ", ")
            print("  Row \(i) [\(classified.role)]: \(texts)")
        }
        #endif

        // Step 4: Build RecognizedTable from classified rows
        var headerSeen = false
        var averagesAssigned = false

        for classified in classifiedRows {
            switch classified.role {
            case .workoutType:
                if table.workoutType == nil {
                    table.workoutType = extractWorkoutType(from: classified.results)
                }

            case .date:
                if table.date == nil {
                    table.date = extractDate(from: classified.results)
                }

            case .header:
                headerSeen = true

            case .dataRow:
                guard let parsed = classified.parsedData else { continue }
                let tableRow = buildTableRow(from: parsed, results: classified.results)

                guard isValidRow(tableRow) else { continue }

                // First data row after header = averages
                if headerSeen && !averagesAssigned {
                    table.averages = tableRow
                    table.totalTime = tableRow.time?.text
                    averagesAssigned = true
                } else {
                    table.rows.append(tableRow)
                }

            case .unknown:
                break
            }
        }

        // Step 5: Detect workout category
        if let workoutType = table.workoutType {
            table.category = patternMatcher.detectWorkoutCategory(workoutType)
        }

        // Step 6: Calculate average confidence
        table.averageConfidence = calculateAverageConfidence(table)

        #if DEBUG
        print("=== Parse Result ===")
        print("Workout type: \(table.workoutType ?? "nil")")
        print("Date: \(table.date?.description ?? "nil")")
        print("Category: \(table.category?.rawValue ?? "nil")")
        print("Averages: time=\(table.averages?.time?.text ?? "nil") " +
              "meters=\(table.averages?.meters?.text ?? "nil") " +
              "split=\(table.averages?.splitPer500m?.text ?? "nil") " +
              "rate=\(table.averages?.strokeRate?.text ?? "nil")")
        print("Rows: \(table.rows.count)")
        for (i, row) in table.rows.enumerated() {
            print("  Row \(i): time=\(row.time?.text ?? "nil") " +
                  "meters=\(row.meters?.text ?? "nil") " +
                  "split=\(row.splitPer500m?.text ?? "nil") " +
                  "rate=\(row.strokeRate?.text ?? "nil")")
        }
        print("Confidence: \(table.averageConfidence)")
        #endif

        return table
    }

    // MARK: - Private: Build TableRow

    private func buildTableRow(
        from parsed: RowClassifier.ParsedRowData,
        results: [GuideRelativeOCRResult]
    ) -> TableRow {
        var row = TableRow()

        // Calculate bounding box from all results
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = 0
        for r in results {
            let box = r.guideRelativeBox
            minX = min(minX, box.minX)
            maxX = max(maxX, box.maxX)
            minY = min(minY, box.minY)
            maxY = max(maxY, box.maxY)
        }
        row.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        row.time = parsed.time
        row.meters = parsed.meters
        row.splitPer500m = parsed.split
        row.strokeRate = parsed.strokeRate

        return row
    }

    // MARK: - Private: Extraction Helpers

    private func extractWorkoutType(from results: [GuideRelativeOCRResult]) -> String? {
        for result in results {
            let text = result.text.trimmingCharacters(in: .whitespaces)
            if patternMatcher.matchWorkoutType(text) { return text }
            let cleaned = patternMatcher.cleanText(text)
            if patternMatcher.matchWorkoutType(cleaned) { return cleaned }
        }
        // Try combining adjacent results (Vision may split "3x4:00/3:00r")
        let combined = results
            .sorted { $0.guideRelativeBox.minX < $1.guideRelativeBox.minX }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "")
        if patternMatcher.matchWorkoutType(combined) { return combined }
        let cleanedCombined = patternMatcher.cleanText(combined)
        if patternMatcher.matchWorkoutType(cleanedCombined) { return cleanedCombined }
        return nil
    }

    private func extractDate(from results: [GuideRelativeOCRResult]) -> Date? {
        for result in results {
            let text = result.text.trimmingCharacters(in: .whitespaces)
            if let date = patternMatcher.matchDate(text) { return date }
        }
        // Try combining adjacent results (Vision may split "Dec 20 2025")
        let combined = results
            .sorted { $0.guideRelativeBox.minX < $1.guideRelativeBox.minX }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return patternMatcher.matchDate(combined)
    }

    private func isValidRow(_ row: TableRow) -> Bool {
        let populated = [
            row.time != nil,
            row.meters != nil,
            row.splitPer500m != nil,
            row.strokeRate != nil
        ].filter { $0 }.count
        return populated >= 2
    }

    // MARK: - Private: Confidence

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
