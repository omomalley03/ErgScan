import Foundation
import CoreGraphics

/// Classifies rows of OCR results using pattern matching (not zone positions).
/// Replaces the zone-based classification approach with a pattern-first strategy.
struct RowClassifier {

    private let patternMatcher = TextPatternMatcher()

    // MARK: - Types

    /// Semantic role of a row on the erg monitor
    enum RowRole {
        case workoutType
        case date
        case header
        case dataRow
        case unknown
    }

    /// Classification result for a single row
    struct ClassifiedRow {
        let role: RowRole
        let results: [GuideRelativeOCRResult]
        let parsedData: ParsedRowData?
    }

    /// Parsed numeric data extracted from a data row
    struct ParsedRowData {
        var time: OCRResult?
        var meters: OCRResult?
        var split: OCRResult?
        var strokeRate: OCRResult?
    }

    // MARK: - Public API

    /// Classify all rows and return structured results.
    /// Rows should be sorted top-to-bottom, each row sorted left-to-right.
    func classifyRows(_ rows: [[GuideRelativeOCRResult]]) -> [ClassifiedRow] {
        rows.map { classifySingleRow($0) }
    }

    // MARK: - Single Row Classification

    private func classifySingleRow(_ row: [GuideRelativeOCRResult]) -> ClassifiedRow {
        let classifications = row.map { result in
            (result: result, dataType: patternMatcher.classify(result.text))
        }

        // 1. Workout type: any element matches
        if classifications.contains(where: { $0.dataType == .workoutType }) {
            return ClassifiedRow(role: .workoutType, results: row, parsedData: nil)
        }

        // 2. Date: any element matches
        if classifications.contains(where: { $0.dataType == .date }) {
            return ClassifiedRow(role: .date, results: row, parsedData: nil)
        }

        // 3. Header: 2+ elements are header labels
        let headerCount = classifications.filter { $0.dataType == .headerLabel }.count
        if headerCount >= 2 {
            return ClassifiedRow(role: .header, results: row, parsedData: nil)
        }

        // 4. Data row: 2+ numeric elements
        let numericTypes: Set<TextPatternMatcher.DataType> = [.timeLikeSplit, .meters, .strokeRate]
        let numericCount = classifications.filter { numericTypes.contains($0.dataType) }.count

        if numericCount >= 2 {
            let parsed = parseDataRow(classifications)
            return ClassifiedRow(role: .dataRow, results: row, parsedData: parsed)
        }

        return ClassifiedRow(role: .unknown, results: row, parsedData: nil)
    }

    // MARK: - Data Row Parsing

    private func parseDataRow(
        _ classifications: [(result: GuideRelativeOCRResult, dataType: TextPatternMatcher.DataType)]
    ) -> ParsedRowData {
        var data = ParsedRowData()

        // Collect time/split candidates with their X positions
        var timeSplitCandidates: [(result: GuideRelativeOCRResult, cleaned: String, midX: CGFloat)] = []

        for (result, dataType) in classifications {
            let cleaned = patternMatcher.cleanText(result.text)

            switch dataType {
            case .meters where data.meters == nil:
                data.meters = OCRResult(
                    text: cleaned,
                    confidence: result.confidence,
                    boundingBox: result.original.boundingBox
                )

            case .strokeRate where data.strokeRate == nil:
                data.strokeRate = OCRResult(
                    text: cleaned,
                    confidence: result.confidence,
                    boundingBox: result.original.boundingBox
                )

            case .timeLikeSplit:
                timeSplitCandidates.append((result, cleaned, result.guideRelativeBox.midX))

            default:
                break
            }
        }

        // Disambiguate time vs split by relative X position within the row
        disambiguateTimeSplit(timeSplitCandidates, into: &data)

        return data
    }

    /// Given time/split candidates, the leftmost is time, the next is split.
    private func disambiguateTimeSplit(
        _ candidates: [(result: GuideRelativeOCRResult, cleaned: String, midX: CGFloat)],
        into data: inout ParsedRowData
    ) {
        let sorted = candidates.sorted { $0.midX < $1.midX }

        if sorted.count >= 2 {
            // Leftmost = time, second = split
            data.time = makeOCR(sorted[0].cleaned, from: sorted[0].result)
            data.split = makeOCR(sorted[1].cleaned, from: sorted[1].result)
        } else if sorted.count == 1 {
            // Single value: use absolute X threshold as fallback
            let candidate = sorted[0]
            if candidate.midX < 0.42 {
                data.time = makeOCR(candidate.cleaned, from: candidate.result)
            } else {
                data.split = makeOCR(candidate.cleaned, from: candidate.result)
            }
        }
    }

    private func makeOCR(_ cleaned: String, from result: GuideRelativeOCRResult) -> OCRResult {
        OCRResult(
            text: cleaned,
            confidence: result.confidence,
            boundingBox: result.original.boundingBox
        )
    }
}
