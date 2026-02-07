import Foundation
import CoreGraphics

/// Spatial grouping of OCR results by bounding box proximity.
struct BoundingBoxAnalyzer {

    // MARK: - Row Grouping (guide-relative, top-left origin)

    /// Group guide-relative results into rows based on Y proximity.
    /// Sorted top-to-bottom (ascending Y since top-left origin).
    func groupIntoRows(
        _ results: [GuideRelativeOCRResult],
        tolerance: CGFloat = 0.03
    ) -> [[GuideRelativeOCRResult]] {
        guard !results.isEmpty else { return [] }

        var rows: [[GuideRelativeOCRResult]] = []

        // Sort top-to-bottom (ascending Y in top-left origin)
        let sorted = results.sorted { $0.guideRelativeBox.midY < $1.guideRelativeBox.midY }

        for result in sorted {
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.guideRelativeBox.midY - result.guideRelativeBox.midY) < tolerance
            }) {
                rows[rowIndex].append(result)
            } else {
                rows.append([result])
            }
        }

        // Sort each row left-to-right
        return rows.map { row in
            row.sorted { $0.guideRelativeBox.minX < $1.guideRelativeBox.minX }
        }
    }

    // MARK: - Utilities

    /// Calculate average confidence for a group of results
    func averageConfidence(_ results: [GuideRelativeOCRResult]) -> Double {
        guard !results.isEmpty else { return 0.0 }
        let sum = results.reduce(0.0) { $0 + Double($1.confidence) }
        return sum / Double(results.count)
    }
}
