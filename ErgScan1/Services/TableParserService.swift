import Foundation
import CoreGraphics

/// Parses OCR results from a Concept2 PM5 monitor into structured workout data.
///
/// Pipeline:
/// 1. Group OCR detections into rows by Y-coordinate clustering
/// 2. Join fragments per row, normalize text
/// 3. Find "View Detail" anchor row
/// 4. Extract workout descriptor, classify as intervals or single
/// 5. Extract date and total time
/// 6. Determine column order from header row
/// 7. Parse summary (averages) row
/// 8. Parse data rows (intervals or splits)
/// 9. Validate and calculate confidence
class TableParserService {

    private let boxAnalyzer = BoundingBoxAnalyzer()
    private let matcher = TextPatternMatcher()

    /// Debug log buffer
    private var debugLog: [String] = []

    // MARK: - Internal Types

    /// A row of OCR results with joined text for pattern matching
    private struct RowData {
        let index: Int
        let joinedText: String          // Fragments joined with spaces
        let normalizedText: String      // After normalize()
        let fragments: [GuideRelativeOCRResult]
    }

    /// Column types for data rows
    private enum Column {
        case time, meters, split, rate, heartRate, unknown
    }

    // MARK: - Public API

    func parseTable(from results: [GuideRelativeOCRResult]) -> (table: RecognizedTable, debugLog: String) {
        debugLog = []
        var table = RecognizedTable()

        log("=== STARTING OCR PARSING ===")
        log("Total OCR observations: \(results.count)")

        guard !results.isEmpty else {
            log("No OCR results to parse")
            return (table, debugLog.joined(separator: "\n"))
        }

        // Log raw OCR results
        log("\n--- RAW OCR RESULTS ---")
        for (idx, result) in results.enumerated() {
            let box = result.guideRelativeBox
            log("[\(idx)] '\(result.text)' | conf: \(String(format: "%.3f", result.confidence)) | y: \(String(format: "%.3f", box.origin.y)) | x: \(String(format: "%.3f", box.origin.x))-\(String(format: "%.3f", box.origin.x + box.size.width))")
        }

        // Phase 1: Group into rows and build RowData
        log("\n=== PHASE 1: GROUPING INTO ROWS ===")
        let rawRows = boxAnalyzer.groupIntoRows(results)
        log("Grouped \(results.count) observations into \(rawRows.count) rows by Y-coordinate clustering")

        let rows = prepareRows(rawRows)
        log("\n--- PREPARED ROWS WITH NORMALIZATION ---")
        for row in rows {
            let yPos = row.fragments.first?.guideRelativeBox.midY ?? 0
            log("Row \(row.index) (Y≈\(String(format: "%.3f", yPos)))")
            log("  Raw:        \"\(row.joinedText)\"")
            log("  Normalized: \"\(row.normalizedText)\"")
            if row.joinedText != row.normalizedText {
                log("  [Normalization changed text]")
            }
        }

        // Phase 2: Find "View Detail" anchor
        log("\n=== PHASE 2: FINDING 'VIEW DETAIL' ANCHOR ===")
        guard let anchorIndex = findViewDetailRow(rows) else {
            log("❌ FAILED: View Detail landmark not found in any row")
            return (table, debugLog.joined(separator: "\n"))
        }
        log("✓ Found 'View Detail' anchor at row \(anchorIndex)")

        // Phase 3: Extract descriptor and classify workout
        log("\n=== PHASE 3: EXTRACT DESCRIPTOR & CLASSIFY WORKOUT ===")
        let descriptorIndex = anchorIndex + 1
        if descriptorIndex < rows.count {
            let descriptor = extractDescriptor(from: rows[descriptorIndex])
            table.description = descriptor
            log("Examining row \(descriptorIndex) for workout descriptor...")
            log("Extracted descriptor: \"\(descriptor ?? "nil")\"")

            if let desc = descriptor {
                // Try interval classification first
                log("Attempting to parse as interval workout...")
                if let interval = matcher.parseIntervalWorkout(desc) {
                    table.category = .interval
                    table.isVariableInterval = interval.isVariable
                    table.workoutType = desc  // Temporary — will be replaced after parsing for variable
                    table.reps = interval.reps
                    table.workPerRep = interval.isVariable ? nil : interval.workTime
                    table.restPerRep = interval.restTime
                    log("✓ Classified as \(interval.isVariable ? "VARIABLE " : "")INTERVALS")
                    log("  Reps: \(interval.reps)")
                    if !interval.isVariable {
                        log("  Work per rep: \(interval.workTime)")
                    }
                    log("  Rest per rep: \(interval.restTime)")
                } else {
                    log("Not an interval pattern, checking general workout type...")
                    if matcher.matchWorkoutType(desc) {
                        table.category = matcher.detectWorkoutCategory(desc)
                        table.workoutType = desc
                        let categoryName = table.category == .interval ? "INTERVALS" : "SINGLE"
                        log("✓ Classified as \(categoryName) (via category detection)")
                        log("  Descriptor: \(desc)")
                    } else {
                        // Store descriptor even if can't classify yet
                        table.workoutType = desc
                        log("⚠️ Unclassified descriptor - will attempt fallback classification later")
                    }
                }
            } else {
                log("⚠️ No descriptor found in row \(descriptorIndex)")
            }
        } else {
            log("⚠️ Descriptor row \(descriptorIndex) is out of bounds")
        }

        // Phase 4: Extract date and total time
        log("\n=== PHASE 4: EXTRACT DATE & TOTAL TIME ===")
        let metadataIndex = anchorIndex + 2
        if metadataIndex < rows.count {
            log("Examining row \(metadataIndex) for metadata...")
            let (date, totalTime) = extractDateAndTime(from: rows[metadataIndex])
            table.date = date
            table.totalTime = totalTime
            if let d = date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                log("✓ Date found: \(formatter.string(from: d))")
            } else {
                log("⚠️ No date found")
            }
            if let tt = totalTime {
                log("✓ Total time found: \(tt)")
            } else {
                log("⚠️ No total time found")
            }
        } else {
            log("⚠️ Metadata row \(metadataIndex) is out of bounds")
        }

        // Phase 5: Determine column order from header row
        log("\n=== PHASE 5: DETERMINE COLUMN ORDER ===")
        let headerIndex = anchorIndex + 3
        var columnOrder: [Column] = []
        if headerIndex < rows.count {
            log("Examining row \(headerIndex) for column headers...")
            columnOrder = determineColumnOrder(from: rows[headerIndex])
            if !columnOrder.isEmpty {
                log("✓ Detected column order: \(columnOrder.map { "\($0)" }.joined(separator: " | "))")
            } else {
                log("⚠️ No column headers detected")
            }
        } else {
            log("⚠️ Header row \(headerIndex) is out of bounds")
        }
        if columnOrder.isEmpty {
            columnOrder = [.time, .meters, .split, .rate]
            log("Using default column order: time | meters | split | rate")
        }

        // Phase 6: Parse summary/averages row (first data row)
        log("\n=== PHASE 6: PARSE SUMMARY ROW ===")
        let summaryIndex = anchorIndex + 4
        if summaryIndex < rows.count {
            log("Parsing summary row \(summaryIndex)...")
            if let avg = parseDataRow(rows[summaryIndex], columnOrder: columnOrder) {
                table.averages = avg
                log("✓ Summary row parsed:")
                log("  Time:  \(avg.time?.text ?? "-")")
                log("  Meters: \(avg.meters?.text ?? "-")")
                log("  Split: \(avg.splitPer500m?.text ?? "-")")
                log("  Rate:  \(avg.strokeRate?.text ?? "-")")
            } else {
                log("❌ Failed to parse summary row (insufficient fields)")
            }
        } else {
            log("⚠️ Summary row \(summaryIndex) is out of bounds")
        }

        // Phase 7: Parse data rows (intervals or splits)
        log("\n=== PHASE 7: PARSE DATA ROWS ===")
        let dataStartIndex = anchorIndex + 5
        var dataRows: [TableRow] = []
        log("Parsing data rows starting from row \(dataStartIndex)...")

        if table.isVariableInterval == true {
            // Variable intervals: re-group fragments with tight Y-threshold
            // The default Y-clustering often merges rest rows with adjacent data rows
            // because they're very close together on the PM5 screen (~0.030 apart).
            // Re-grouping with a tighter threshold (0.015) correctly separates them.
            dataRows = parseVariableIntervalRows(allRows: rows, from: dataStartIndex, columnOrder: columnOrder)
        } else {
            // Standard processing for fixed intervals and single pieces
            for i in dataStartIndex..<rows.count {
                if let row = parseDataRow(rows[i], columnOrder: columnOrder) {
                    dataRows.append(row)
                    log("✓ Row \(i): time=\(row.time?.text ?? "-"), meters=\(row.meters?.text ?? "-"), split=\(row.splitPer500m?.text ?? "-"), rate=\(row.strokeRate?.text ?? "-")")
                } else {
                    log("  Row \(i): skipped (insufficient fields)")
                }
            }
        }
        table.rows = dataRows
        log("Parsed \(dataRows.count) data rows total")

        // Variable Interval Naming
        // For variable intervals, the descriptor is truncated and unreliable.
        // Generate the workout name from the parsed interval meters.
        if table.isVariableInterval == true && !dataRows.isEmpty {
            log("\n--- VARIABLE INTERVAL NAMING ---")
            let metersComponents = dataRows.enumerated().map { (index, row) -> String in
                if let meters = row.meters?.text {
                    return "\(meters)m"
                } else {
                    // Interval parsed but no meters - use time as identifier
                    if let time = row.time?.text {
                        return time.replacingOccurrences(of: ".0", with: "")
                    } else {
                        return "interval\(index + 1)"
                    }
                }
            }
            let generatedName = metersComponents.joined(separator: " / ")
            table.workoutType = generatedName
            table.description = generatedName
            log("✓ Generated variable interval name: \"\(generatedName)\"")
            log("  Intervals used: \(metersComponents.joined(separator: ", "))")
        }

        // Update reps count from data rows for variable intervals
        if table.isVariableInterval == true {
            table.reps = dataRows.count
            log("  Updated variable interval reps from data rows: \(dataRows.count)")
        }

        // Phase 8: Fallback classification if descriptor was unreadable
        log("\n=== PHASE 8: FALLBACK CLASSIFICATION ===")
        if table.category == nil && !dataRows.isEmpty {
            log("Category not determined from descriptor, using fallback classification...")
            table.category = fallbackClassification(summaryRow: table.averages, dataRows: dataRows)
            log("✓ Fallback result: \(table.category?.rawValue ?? "nil")")
        } else if table.category != nil {
            log("Category already determined: \(table.category!.rawValue)")
        } else {
            log("No data rows to classify")
        }

        // Phase 9: Compute total distance and confidence
        log("\n=== PHASE 9: COMPUTE TOTALS & CONFIDENCE ===")
        table.totalDistance = computeTotalDistance(summary: table.averages, dataRows: dataRows)
        if let dist = table.totalDistance {
            log("Total distance: \(dist)m")
        } else {
            log("Total distance: not available")
        }
        table.averageConfidence = calculateAverageConfidence(table)
        log("Average confidence: \(String(format: "%.1f%%", table.averageConfidence * 100))")

        log("\n=== PARSING COMPLETE ===")
        log("Data rows: \(dataRows.count)")
        log("Category: \(table.category?.rawValue ?? "unknown")")
        log("Overall confidence: \(String(format: "%.0f%%", table.averageConfidence * 100))")

        return (table, debugLog.joined(separator: "\n"))
    }

    // MARK: - Debug Logging

    private func log(_ message: String) {
        debugLog.append(message)
    }

    // MARK: - Phase 1: Row Preparation

    private func prepareRows(_ rawRows: [[GuideRelativeOCRResult]]) -> [RowData] {
        rawRows.enumerated().map { (index, fragments) in
            let joined = fragments.map { $0.text }.joined(separator: " ")
            let normalized = matcher.normalize(joined)
            return RowData(
                index: index,
                joinedText: joined,
                normalizedText: normalized,
                fragments: fragments
            )
        }
    }

    // MARK: - Phase 2: Landmark Detection

    private func findViewDetailRow(_ rows: [RowData]) -> Int? {
        for row in rows {
            // Check joined text
            let joinedMatch = matcher.matchLandmark(row.joinedText)
            let normalizedMatch = matcher.matchLandmark(row.normalizedText)

            log("Checking row \(row.index): '\(row.joinedText)'")

            if joinedMatch == .viewDetail {
                log("  ✓ Match on joined text")
                return row.index
            }
            if normalizedMatch == .viewDetail {
                log("  ✓ Match on normalized text")
                return row.index
            }

            // Check individual fragments
            for fragment in row.fragments {
                let norm = matcher.normalize(fragment.text)
                if matcher.matchLandmark(fragment.text) == .viewDetail {
                    log("  ✓ Match on fragment: '\(fragment.text)'")
                    return row.index
                }
                if matcher.matchLandmark(norm) == .viewDetail {
                    log("  ✓ Match on normalized fragment: '\(norm)'")
                    return row.index
                }
            }
        }
        return nil
    }

    // MARK: - Phase 3: Descriptor Extraction

    private func extractDescriptor(from row: RowData) -> String? {
        log("Trying to extract descriptor from row fragments...")

        // Try each fragment individually (using descriptor-specific normalization)
        for (idx, fragment) in row.fragments.enumerated() {
            let normalized = matcher.normalizeDescriptor(fragment.text)
            log("  Fragment \(idx): '\(fragment.text)' -> normalized: '\(normalized)'")

            if matcher.matchWorkoutType(normalized) {
                log("    ✓ Matches workout type pattern")
                return normalized
            }
        }

        // Try the joined text with descriptor normalization
        log("Trying joined text: '\(row.joinedText)'")
        let normalized = matcher.normalizeDescriptor(row.joinedText)
        if normalized != row.joinedText {
            log("  Normalized: '\(normalized)'")
        }
        if matcher.matchWorkoutType(normalized) {
            log("  ✓ Joined text matches")
            return normalized
        }

        // Try splitting joined text on spaces and checking each part
        let parts = row.joinedText.split(separator: " ").map(String.init)
        if parts.count > 1 {
            log("Trying individual parts from joined text...")
            for (idx, part) in parts.enumerated() {
                log("  Part \(idx): '\(part)'")
                let normalizedPart = matcher.normalizeDescriptor(part)
                if normalizedPart != part {
                    log("    Normalized: '\(normalizedPart)'")
                }
                if matcher.matchWorkoutType(normalizedPart) {
                    log("    ✓ Matches")
                    return normalizedPart
                }
            }
        }

        log("  ❌ No descriptor pattern matched")
        return nil
    }

    // MARK: - Phase 4: Date & Time Extraction

    private func extractDateAndTime(from row: RowData) -> (Date?, String?) {
        var date: Date? = nil
        var totalTime: String? = nil

        log("Scanning fragments for date and time...")
        // Try individual fragments first
        for (idx, fragment) in row.fragments.enumerated() {
            let text = fragment.text
            let normalized = matcher.normalize(text)
            log("  Fragment \(idx): '\(text)'")

            if date == nil, let d = matcher.matchDate(text) {
                log("    ✓ Matched as date")
                date = d
                continue
            }
            if totalTime == nil, matcher.matchTotalTime(normalized) {
                log("    ✓ Matched as total time: '\(normalized)'")
                totalTime = normalized
                continue
            }
        }

        // Try splitting the joined text if still missing fields
        if date == nil || totalTime == nil {
            log("Trying joined text parts...")
            let parts = row.joinedText.split(separator: " ").map(String.init)
            // Try combining consecutive parts for date (e.g., "Oct", "20", "2024")
            if date == nil {
                for i in 0..<parts.count {
                    // Try 3-word date: "Oct 20 2024"
                    if i + 2 < parts.count {
                        let candidate = "\(parts[i]) \(parts[i+1]) \(parts[i+2])"
                        log("  Trying date candidate: '\(candidate)'")
                        if let d = matcher.matchDate(candidate) {
                            log("    ✓ Matched as date")
                            date = d
                            break
                        }
                    }
                }
            }
            // Try each part for total time
            if totalTime == nil {
                for part in parts {
                    let normalized = matcher.normalize(part)
                    if matcher.matchTotalTime(normalized) {
                        log("  ✓ Part '\(part)' matched as total time: '\(normalized)'")
                        totalTime = normalized
                        break
                    }
                }
            }
        }

        return (date, totalTime)
    }

    // MARK: - Phase 5: Column Order Detection

    private func determineColumnOrder(from row: RowData) -> [Column] {
        log("Analyzing header row for column positions...")

        // Collect all text items with X positions
        var items: [(text: String, midX: CGFloat)] = []

        for fragment in row.fragments {
            let normalized = matcher.normalize(fragment.text)
            let split = matcher.splitSmooshedText(normalized)
            log("  Fragment: '\(fragment.text)' -> normalized: '\(normalized)'")
            if split.count > 1 {
                log("    Split into: \(split.joined(separator: " | "))")
            }

            for (i, text) in split.enumerated() {
                let x = fragment.guideRelativeBox.midX + CGFloat(i) * 0.001
                items.append((text, x))
            }
        }

        // Sort left to right
        items.sort { $0.midX < $1.midX }
        log("Sorted items left-to-right: \(items.map { $0.text }.joined(separator: " | "))")

        // Map landmark text to column type
        var columns: [Column] = []
        for (text, _) in items {
            if let landmark = matcher.matchLandmark(text) {
                let columnType: Column
                switch landmark {
                case .time:
                    columnType = .time
                    columns.append(.time)
                case .meter:
                    columnType = .meters
                    columns.append(.meters)
                case .split500m:
                    columnType = .split
                    columns.append(.split)
                case .strokeRateHeader:
                    columnType = .rate
                    columns.append(.rate)
                default:
                    continue
                }
                log("  '\(text)' -> \(columnType)")
            }
        }

        // Fallback: If we have 4 items but only 3 columns detected, assume the 4th is rate
        if items.count == 4 && columns.count == 3 && !columns.contains(.rate) {
            log("  Fallback: Detected 4 header items but only 3 columns, adding rate as 4th column")
            columns.append(.rate)
        }

        // Second fallback: PM5 always displays 4 columns (time, meters, /500m, s/m)
        // If we detected the standard 3 columns but not rate, always append it
        if columns.count == 3 && !columns.contains(.rate) &&
           columns.contains(.time) && columns.contains(.meters) && columns.contains(.split) {
            log("  Fallback: Standard 3-column layout detected, appending rate as 4th column (PM5 always has 4 columns)")
            columns.append(.rate)
        }

        return columns
    }

    // MARK: - Phase 6 & 7: Data Row Parsing

    private func parseDataRow(_ row: RowData, columnOrder: [Column]) -> TableRow? {
        var tableRow = TableRow()
        var fieldCount = 0

        log("    Parsing row \(row.index): '\(row.joinedText)'")

        // Build list of values from fragments, splitting smooshed text
        var values: [(text: String, midX: CGFloat, fragment: GuideRelativeOCRResult)] = []

        for fragment in row.fragments {
            let normalized = matcher.normalize(fragment.text)

            // Skip junk labels
            if matcher.isJunk(fragment.text) || matcher.isJunk(normalized) {
                log("      Skipping junk: '\(fragment.text)'")
                continue
            }

            // Handle combined split+rate
            if let combined = matcher.parseCombinedSplitRate(normalized) {
                log("      Split combined split+rate: '\(normalized)' -> '\(combined.split)' + '\(combined.rate)'")
                values.append((combined.split, fragment.guideRelativeBox.midX, fragment))
                values.append((combined.rate, fragment.guideRelativeBox.midX + 0.01, fragment))
                continue
            }

            // Split smooshed text
            let split = matcher.splitSmooshedText(normalized)
            if split.count > 1 {
                log("      Split smooshed text: '\(normalized)' -> \(split.joined(separator: " | "))")
            }
            for (i, text) in split.enumerated() {
                let x = fragment.guideRelativeBox.midX + CGFloat(i) * 0.001
                values.append((text, x, fragment))
            }
        }

        // Sort left to right
        values.sort { $0.midX < $1.midX }
        log("      Values (L-R): \(values.map { $0.text }.joined(separator: " | "))")

        // Assign values to columns by position
        for (i, column) in columnOrder.enumerated() {
            guard i < values.count else { break }
            let (text, _, fragment) = values[i]

            let ocr = OCRResult(
                text: text,
                confidence: fragment.confidence,
                boundingBox: fragment.original.boundingBox
            )

            switch column {
            case .time:
                if matcher.matchTime(text) || matcher.matchSplit(text) {
                    log("      Assigned '\(text)' to TIME")
                    tableRow.time = ocr
                    fieldCount += 1
                }
            case .meters:
                if matcher.matchMeters(text) {
                    log("      Assigned '\(text)' to METERS")
                    tableRow.meters = ocr
                    fieldCount += 1
                }
            case .split:
                if matcher.matchSplit(text) || matcher.matchTime(text) {
                    log("      Assigned '\(text)' to SPLIT")
                    tableRow.splitPer500m = ocr
                    fieldCount += 1
                }
            case .rate:
                if matcher.matchRate(text) {
                    log("      Assigned '\(text)' to RATE")
                    tableRow.strokeRate = ocr
                    fieldCount += 1
                }
            case .heartRate:
                if let val = Int(text), val >= 40, val <= 220 {
                    log("      Assigned '\(text)' to HEART RATE")
                    tableRow.heartRate = ocr
                    fieldCount += 1
                }
            case .unknown:
                break
            }
        }

        // Calculate bounding box
        if !row.fragments.isEmpty {
            let boxes = row.fragments.map { $0.guideRelativeBox }
            let minX = boxes.map { $0.minX }.min() ?? 0
            let maxX = boxes.map { $0.maxX }.max() ?? 0
            let minY = boxes.map { $0.minY }.min() ?? 0
            let maxY = boxes.map { $0.maxY }.max() ?? 0
            tableRow.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        // Require at least 2 populated fields
        if fieldCount >= 2 {
            log("      ✓ Row valid (\(fieldCount) fields)")
            return tableRow
        } else {
            log("      ❌ Row invalid (only \(fieldCount) fields)")
            return nil
        }
    }

    // MARK: - Phase 8: Fallback Classification

    /// If descriptor was unreadable, classify by analyzing data row patterns
    private func fallbackClassification(summaryRow: TableRow?, dataRows: [TableRow]) -> WorkoutCategory {
        guard let summary = summaryRow, let summaryTime = summary.time?.text,
              let firstData = dataRows.first, let firstTime = firstData.time?.text else {
            return .single
        }

        // If summary time is significantly larger than first data row time, likely intervals
        let summarySeconds = approximateSeconds(summaryTime)
        let firstSeconds = approximateSeconds(firstTime)

        if summarySeconds > 0 && firstSeconds > 0 && summarySeconds > firstSeconds * 1.5 {
            return .interval
        }

        return .single
    }

    /// Rough conversion of time string to seconds for comparison
    private func approximateSeconds(_ timeStr: String) -> Double {
        let parts = timeStr.replacingOccurrences(of: ".", with: ":").split(separator: ":")
        var seconds = 0.0
        for (i, part) in parts.reversed().enumerated() {
            if let val = Double(part) {
                switch i {
                case 0: seconds += val         // seconds or tenths
                case 1: seconds += val * 60    // minutes or seconds
                case 2: seconds += val * 3600  // hours or minutes
                case 3: seconds += val * 3600  // hours
                default: break
                }
            }
        }
        return seconds
    }

    // MARK: - Phase 9: Totals & Confidence

    private func computeTotalDistance(summary: TableRow?, dataRows: [TableRow]) -> Int? {
        // Try summary row first
        if let metersText = summary?.meters?.text, let meters = Int(metersText) {
            return meters
        }
        // Sum data rows
        let sum = dataRows.compactMap { row -> Int? in
            guard let text = row.meters?.text else { return nil }
            return Int(text)
        }.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    private func calculateAverageConfidence(_ table: RecognizedTable) -> Double {
        var allRows = table.rows
        if let avg = table.averages { allRows.append(avg) }

        var sum = 0.0
        var count = 0

        for row in allRows {
            for field in [row.time, row.meters, row.splitPer500m, row.strokeRate, row.heartRate] {
                if let f = field {
                    sum += Double(f.confidence)
                    count += 1
                }
            }
        }

        return count > 0 ? sum / Double(count) : 0.0
    }

    // MARK: - Variable Interval Data Row Parsing

    /// For variable intervals, re-group individual OCR fragments with tight Y-clustering
    /// to correctly separate rest rows from data rows that the default grouping merges.
    ///
    /// The PM5 displays variable intervals with interleaved rest rows (~0.030 apart in Y),
    /// which is too close for the default Y-clustering threshold. This method:
    /// 1. Collects all fragments from the data area
    /// 2. Sorts by Y and groups with 0.015 threshold
    /// 3. Identifies rest groups (starting with r/г/tr/· + time pattern)
    /// 4. Parses non-rest groups as data rows
    private func parseVariableIntervalRows(
        allRows: [RowData],
        from startIndex: Int,
        columnOrder: [Column]
    ) -> [TableRow] {
        var dataRows: [TableRow] = []

        // Collect ALL individual fragments from the data area
        var fragments: [GuideRelativeOCRResult] = []
        for i in startIndex..<allRows.count {
            fragments.append(contentsOf: allRows[i].fragments)
        }

        log("  Variable interval mode: collected \(fragments.count) fragments from data area")

        // Sort by Y position
        fragments.sort { $0.guideRelativeBox.midY < $1.guideRelativeBox.midY }

        // Group by Y with tight threshold (0.015) to separate rest rows from data rows
        // Within a PM5 row, fragments are within ~0.003 of each other
        // Between adjacent rows (data↔rest), the gap is ~0.030
        // So 0.015 correctly separates them
        var groups: [[GuideRelativeOCRResult]] = []
        var currentGroup: [GuideRelativeOCRResult] = []
        var groupStartY: CGFloat = -1

        for fragment in fragments {
            let y = fragment.guideRelativeBox.midY
            if currentGroup.isEmpty {
                currentGroup.append(fragment)
                groupStartY = y
            } else if abs(y - groupStartY) < 0.015 {
                currentGroup.append(fragment)
            } else {
                groups.append(currentGroup)
                currentGroup = [fragment]
                groupStartY = y
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        log("  Re-grouped into \(groups.count) tight rows")

        // Parse each group
        for (idx, group) in groups.enumerated() {
            // Sort group fragments left-to-right for proper column assignment
            let sortedGroup = group.sorted { $0.guideRelativeBox.midX < $1.guideRelativeBox.midX }

            // Check if this group is a rest row by examining the leftmost fragment
            let firstText = matcher.normalize(sortedGroup[0].text.trimmingCharacters(in: .whitespaces))
            if isRestTimeFragment(firstText) {
                log("  Group \(idx): skipped (rest row, first fragment: '\(sortedGroup[0].text)')")
                continue
            }

            // Build a temporary RowData and parse
            let joined = sortedGroup.map { $0.text }.joined(separator: " ")
            let normalized = matcher.normalize(joined)
            let tempRow = RowData(index: idx, joinedText: joined, normalizedText: normalized, fragments: sortedGroup)

            if let row = parseDataRow(tempRow, columnOrder: columnOrder) {
                dataRows.append(row)
                log("✓ Group \(idx): time=\(row.time?.text ?? "-"), meters=\(row.meters?.text ?? "-"), split=\(row.splitPer500m?.text ?? "-"), rate=\(row.strokeRate?.text ?? "-")")
            } else {
                log("  Group \(idx): skipped (insufficient fields) - '\(joined)'")
            }
        }

        return dataRows
    }

    /// Check if a normalized text fragment is a rest time indicator.
    /// Rest rows on the PM5 start with "r" + time, but OCR often reads the "r" as:
    /// г (Cyrillic), · (middle dot), or adds "t" prefix (tr2:00).
    private func isRestTimeFragment(_ text: String) -> Bool {
        let prefixes = ["r", "г", "tr", "·"]
        for prefix in prefixes {
            if text.hasPrefix(prefix) && text.count >= prefix.count + 4 {
                let afterPrefix = String(text.dropFirst(prefix.count))
                if matcher.matchTime(afterPrefix) || matcher.matches(afterPrefix, pattern: #"^\d{1,2}:\d{2}"#) {
                    return true
                }
            }
        }
        return false
    }
}
