import Foundation
import SwiftUI
import SwiftData
import Combine

enum BenchmarkFilter {
    case all
    case approvedOnly
    case unapprovedOnly
}

enum BenchmarkSortOrder {
    case dateDescending
    case dateAscending
    case accuracyDescending
}

enum RetestMode {
    case full          // Re-run OCR + parsing
    case parsingOnly   // Use cached OCR, only re-run parsing
}

@MainActor
class BenchmarkListViewModel: ObservableObject {
    @Published var selectedFilter: BenchmarkFilter = .all
    @Published var sortOrder: BenchmarkSortOrder = .dateDescending
    @Published var isRetesting: Bool = false
    @Published var retestProgress: Double = 0.0
    @Published var retestStatus: String = ""
    @Published var retestMode: RetestMode = .full

    private let visionService = VisionService()
    private let tableParser = TableParserService()

    /// Retest a single benchmark image
    func retestImage(_ image: BenchmarkImage, context: ModelContext) async {
        guard let rawData = image.imageData, let imageData = UIImage(data: rawData) else {
            print("⚠️ Failed to load image data")
            return
        }

        print("🔄 Retesting image \(image.id)...")

        do {
            // Run OCR
            let ocrResults = try await visionService.recognizeText(in: imageData)

            // Convert to guide-relative coordinates (flip axes for portrait)
            let guideRelativeResults = ocrResults.map { result in
                let box = result.boundingBox
                let flippedBox = CGRect(
                    x: box.origin.y,
                    y: box.origin.x,
                    width: box.height,
                    height: box.width
                )
                return GuideRelativeOCRResult(
                    original: result,
                    guideRelativeBox: flippedBox
                )
            }

            // Parse table
            let parseResult = tableParser.parseTable(from: guideRelativeResults)
            let parsedTable = parseResult.table

            // Store OCR results and parsed table in image
            let encoder = JSONEncoder()
            image.rawOCRResults = try? encoder.encode(guideRelativeResults)
            image.parsedTable = try? encoder.encode(parsedTable)
            image.ocrConfidence = parsedTable.averageConfidence
            image.parserDebugLog = parseResult.debugLog
            image.lastTestedDate = Date()

            // Calculate accuracy if ground truth exists
            if let workout = image.workout {
                image.accuracyScore = calculateAccuracy(parsedTable: parsedTable, groundTruth: workout)
            }

            // Save changes
            try context.save()
            print("✅ Retest complete - Accuracy: \(String(format: "%.0f%%", (image.accuracyScore ?? 0) * 100))")

        } catch {
            print("❌ Retest error: \(error)")
        }
    }

    /// Retest parsing only (uses cached OCR results)
    func retestParsingOnly(_ image: BenchmarkImage, context: ModelContext) async {
        // Use cached rawOCRResults instead of re-running OCR
        guard let rawOCRData = image.rawOCRResults,
              let cachedOCRResults = try? JSONDecoder().decode([GuideRelativeOCRResult].self, from: rawOCRData) else {
            print("⚠️ No cached OCR results - run full retest first")
            return
        }

        print("🔄 Retesting parsing only for image \(image.id)...")

        // Only re-run parsing
        let parseResult = tableParser.parseTable(from: cachedOCRResults)
        let parsedTable = parseResult.table

        // Store updated parsed table
        image.parsedTable = try? JSONEncoder().encode(parsedTable)
        image.ocrConfidence = parsedTable.averageConfidence
        image.parserDebugLog = parseResult.debugLog
        image.lastTestedDate = Date()

        // Calculate accuracy
        if let workout = image.workout {
            image.accuracyScore = calculateAccuracy(parsedTable: parsedTable, groundTruth: workout)
        }

        // Save changes
        try? context.save()
        print("✅ Parser-only retest complete - Accuracy: \(String(format: "%.0f%%", (image.accuracyScore ?? 0) * 100))")
    }

    /// Retest all benchmark images
    func retestAllImages(context: ModelContext) async {
        isRetesting = true
        retestProgress = 0.0

        // Fetch all benchmark images
        let descriptor = FetchDescriptor<BenchmarkImage>(
            sortBy: [SortDescriptor(\.capturedDate)]
        )

        guard let allImages = try? context.fetch(descriptor) else {
            print("❌ Failed to fetch benchmark images")
            isRetesting = false
            return
        }

        let total = allImages.count
        let modeDescription = retestMode == .full ? "Full OCR + Parsing" : "Parsing Only"
        print("🔄 Retesting \(total) benchmark images (\(modeDescription))...")

        for (index, image) in allImages.enumerated() {
            retestStatus = "Testing image \(index + 1) of \(total)"

            switch retestMode {
            case .full:
                await retestImage(image, context: context)
            case .parsingOnly:
                await retestParsingOnly(image, context: context)
            }

            retestProgress = Double(index + 1) / Double(total)
        }

        // Generate aggregate report
        generateAggregateReport(allImages: allImages)

        retestStatus = "Complete"
        isRetesting = false
    }

    /// Calculate accuracy score by comparing parsed table to ground truth
    private func calculateAccuracy(parsedTable: RecognizedTable, groundTruth: BenchmarkWorkout) -> Double {
        var totalFields = 0
        var matchingFields = 0

        // Compare metadata fields
        if let gt = groundTruth.workoutType {
            totalFields += 1
            if parsedTable.workoutType == gt { matchingFields += 1 }
        }

        if let gt = groundTruth.totalTime {
            totalFields += 1
            if parsedTable.totalTime == gt { matchingFields += 1 }
        }

        if let gt = groundTruth.workoutDescription {
            totalFields += 1
            if parsedTable.description == gt { matchingFields += 1 }
        }

        if let gt = groundTruth.totalDistance {
            totalFields += 1
            if parsedTable.totalDistance == gt { matchingFields += 1 }
        }

        // Separate averages (orderIndex = 0) from data rows (orderIndex >= 1)
        let sortedIntervals = (groundTruth.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
        let gtAverages = sortedIntervals.first(where: { $0.orderIndex == 0 })
        let gtDataRows = sortedIntervals.filter { $0.orderIndex >= 1 }

        // Compare averages row
        if let gtAvg = gtAverages, let parsedAvg = parsedTable.averages {
            if let gt = gtAvg.time {
                totalFields += 1
                if parsedAvg.time?.text == gt { matchingFields += 1 }
            }

            if let gt = gtAvg.meters {
                totalFields += 1
                if parsedAvg.meters?.text == String(gt) { matchingFields += 1 }
            }

            if let gt = gtAvg.splitPer500m {
                totalFields += 1
                if parsedAvg.splitPer500m?.text == gt { matchingFields += 1 }
            }

            if let gt = gtAvg.strokeRate {
                totalFields += 1
                if parsedAvg.strokeRate?.text == String(gt) { matchingFields += 1 }
            }

            if let gt = gtAvg.heartRate {
                totalFields += 1
                if parsedAvg.heartRate?.text == String(gt) { matchingFields += 1 }
            }
        }

        // Compare data rows
        for (index, gtInterval) in gtDataRows.enumerated() {
            guard index < parsedTable.rows.count else { continue }
            let parsedRow = parsedTable.rows[index]

            if let gt = gtInterval.time {
                totalFields += 1
                if parsedRow.time?.text == gt { matchingFields += 1 }
            }

            if let gt = gtInterval.meters {
                totalFields += 1
                if parsedRow.meters?.text == String(gt) { matchingFields += 1 }
            }

            if let gt = gtInterval.splitPer500m {
                totalFields += 1
                if parsedRow.splitPer500m?.text == gt { matchingFields += 1 }
            }

            if let gt = gtInterval.strokeRate {
                totalFields += 1
                if parsedRow.strokeRate?.text == String(gt) { matchingFields += 1 }
            }

            if let gt = gtInterval.heartRate {
                totalFields += 1
                if parsedRow.heartRate?.text == String(gt) { matchingFields += 1 }
            }
        }

        return totalFields > 0 ? Double(matchingFields) / Double(totalFields) : 0.0
    }

    /// Generate aggregate statistics report
    private func generateAggregateReport(allImages: [BenchmarkImage]) {
        let imagesWithAccuracy = allImages.filter { $0.accuracyScore != nil }
        guard !imagesWithAccuracy.isEmpty else {
            print("📊 No accuracy data available")
            return
        }

        let totalAccuracy = imagesWithAccuracy.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) }
        let averageAccuracy = totalAccuracy / Double(imagesWithAccuracy.count)

        print("📊 Aggregate Report:")
        print("   Overall accuracy: \(String(format: "%.0f%%", averageAccuracy * 100))")
        print("   Images tested: \(imagesWithAccuracy.count) of \(allImages.count)")

        // Find worst performing images
        let worstImages = imagesWithAccuracy.sorted {
            ($0.accuracyScore ?? 1.0) < ($1.accuracyScore ?? 1.0)
        }.prefix(5)

        print("   Worst performing images:")
        for image in worstImages {
            let score = (image.accuracyScore ?? 0) * 100
            let angle = image.angleDescription ?? "Unknown"
            print("      - \(angle): \(String(format: "%.0f%%", score))")
        }
    }

    /// Generate comprehensive debug report for Claude analysis
    func generateDebugReport(allImages: [BenchmarkImage]) -> String {
        var report = """
        # ErgScan OCR/Parser Benchmark Test Report
        Generated: \(Date().formatted(date: .long, time: .standard))

        ## Executive Summary

        """

        let testedImages = allImages.filter { $0.accuracyScore != nil }
        let totalAccuracy = testedImages.isEmpty ? 0.0 : testedImages.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) } / Double(testedImages.count)

        report += """
        - Total Images: \(allImages.count)
        - Tested Images: \(testedImages.count)
        - Overall Accuracy: \(String(format: "%.1f%%", totalAccuracy * 100))


        """

        // Add detailed test results for each image
        report += "## Detailed Test Results\n\n"

        for (index, image) in allImages.enumerated() {
            report += "### Test Case \(index + 1): \(image.angleDescription ?? "Unknown")\n\n"

            // Image metadata
            report += "**Image Info:**\n"
            report += "- Resolution: \(image.resolution ?? "Unknown")\n"
            report += "- Captured: \(image.capturedDate.formatted(date: .abbreviated, time: .shortened))\n"
            if let lastTest = image.lastTestedDate {
                report += "- Last Tested: \(lastTest.formatted(date: .abbreviated, time: .shortened))\n"
            }
            report += "- OCR Confidence: \(String(format: "%.1f%%", (image.ocrConfidence ?? 0) * 100))\n"
            if let accuracy = image.accuracyScore {
                report += "- Accuracy Score: \(String(format: "%.1f%%", accuracy * 100))\n"
            }
            report += "\n"

            // Ground truth
            if let workout = image.workout {
                report += "**Ground Truth:**\n"
                report += "```\n"
                report += "Workout Type: \(workout.workoutType ?? "nil")\n"
                report += "Description: \(workout.workoutDescription ?? "nil")\n"
                report += "Total Time: \(workout.totalTime ?? "nil")\n"
                if let dist = workout.totalDistance {
                    report += "Total Distance: \(dist)m\n"
                }
                if let reps = workout.reps {
                    report += "Reps: \(reps)\n"
                }
                report += "\nIntervals:\n"
                let sortedIntervals = (workout.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                for (i, interval) in sortedIntervals.enumerated() {
                    report += "  [\(i + 1)] Time: \(interval.time ?? "nil")"
                    if let m = interval.meters { report += ", Meters: \(m)" }
                    if let s = interval.splitPer500m { report += ", Split: \(s)" }
                    if let r = interval.strokeRate { report += ", Rate: \(r)" }
                    if let h = interval.heartRate { report += ", HR: \(h)" }
                    report += "\n"
                }
                report += "```\n\n"
            }

            // Raw OCR data
            if let rawOCRData = image.rawOCRResults,
               let ocrResults = try? JSONDecoder().decode([GuideRelativeOCRResult].self, from: rawOCRData) {
                report += "**Raw OCR Results (\(ocrResults.count) items):**\n"
                report += "```\n"
                for (i, result) in ocrResults.enumerated() {
                    let box = result.guideRelativeBox
                    report += "[\(i + 1)] \"\(result.text)\" (conf: \(String(format: "%.2f", result.confidence)))"
                    report += " @ y=\(String(format: "%.3f", box.origin.y)) x=[\(String(format: "%.3f", box.origin.x))-\(String(format: "%.3f", box.maxX))]\n"
                }
                report += "```\n\n"
            }

            // Parsed table
            if let parsedTableData = image.parsedTable,
               let parsedTable = try? JSONDecoder().decode(RecognizedTable.self, from: parsedTableData) {
                report += "**Parsed Table:**\n"
                report += "```\n"
                report += "Workout Type: \(parsedTable.workoutType ?? "nil")\n"
                report += "Description: \(parsedTable.description ?? "nil")\n"
                report += "Total Time: \(parsedTable.totalTime ?? "nil")\n"
                if let dist = parsedTable.totalDistance {
                    report += "Total Distance: \(dist)m\n"
                }
                if let reps = parsedTable.reps {
                    report += "Reps: \(reps)\n"
                }
                report += "Category: \(parsedTable.category?.rawValue ?? "nil")\n"
                report += "\nData Rows (\(parsedTable.rows.count)):\n"
                for (i, row) in parsedTable.rows.enumerated() {
                    report += "  [\(i + 1)] Time: \(row.time?.text ?? "nil")"
                    if let m = row.meters?.text { report += ", Meters: \(m)" }
                    if let s = row.splitPer500m?.text { report += ", Split: \(s)" }
                    if let r = row.strokeRate?.text { report += ", Rate: \(r)" }
                    if let h = row.heartRate?.text { report += ", HR: \(h)" }
                    report += "\n"
                }
                report += "```\n\n"
            }

            // Field-by-field comparison
            if let workout = image.workout,
               let parsedTableData = image.parsedTable,
               let parsedTable = try? JSONDecoder().decode(RecognizedTable.self, from: parsedTableData) {
                report += "**Field-by-Field Comparison:**\n"
                report += "```\n"

                // Metadata
                report += "Workout Type: \(parsedTable.workoutType == workout.workoutType ? "✓" : "✗") "
                report += "GT=\"\(workout.workoutType ?? "nil")\" Parsed=\"\(parsedTable.workoutType ?? "nil")\"\n"

                report += "Total Time: \(parsedTable.totalTime == workout.totalTime ? "✓" : "✗") "
                report += "GT=\"\(workout.totalTime ?? "nil")\" Parsed=\"\(parsedTable.totalTime ?? "nil")\"\n"

                report += "Description: \(parsedTable.description == workout.workoutDescription ? "✓" : "✗") "
                report += "GT=\"\(workout.workoutDescription ?? "nil")\" Parsed=\"\(parsedTable.description ?? "nil")\"\n"

                // Intervals
                let gtIntervals = (workout.intervals ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
                for (i, gtInterval) in gtIntervals.enumerated() {
                    if i < parsedTable.rows.count {
                        let parsedRow = parsedTable.rows[i]
                        report += "\nInterval \(i + 1):\n"

                        if let gtTime = gtInterval.time {
                            let match = parsedRow.time?.text == gtTime
                            report += "  Time: \(match ? "✓" : "✗") GT=\"\(gtTime)\" Parsed=\"\(parsedRow.time?.text ?? "nil")\"\n"
                        }

                        if let gtMeters = gtInterval.meters {
                            let match = parsedRow.meters?.text == String(gtMeters)
                            report += "  Meters: \(match ? "✓" : "✗") GT=\"\(gtMeters)\" Parsed=\"\(parsedRow.meters?.text ?? "nil")\"\n"
                        }

                        if let gtSplit = gtInterval.splitPer500m {
                            let match = parsedRow.splitPer500m?.text == gtSplit
                            report += "  Split: \(match ? "✓" : "✗") GT=\"\(gtSplit)\" Parsed=\"\(parsedRow.splitPer500m?.text ?? "nil")\"\n"
                        }

                        if let gtRate = gtInterval.strokeRate {
                            let match = parsedRow.strokeRate?.text == String(gtRate)
                            report += "  Rate: \(match ? "✓" : "✗") GT=\"\(gtRate)\" Parsed=\"\(parsedRow.strokeRate?.text ?? "nil")\"\n"
                        }

                        if let gtHR = gtInterval.heartRate {
                            let match = parsedRow.heartRate?.text == String(gtHR)
                            report += "  HR: \(match ? "✓" : "✗") GT=\"\(gtHR)\" Parsed=\"\(parsedRow.heartRate?.text ?? "nil")\"\n"
                        }
                    } else {
                        report += "\nInterval \(i + 1): ✗ Missing in parsed table\n"
                    }
                }
                report += "```\n\n"
            }

            // Parser debug log
            if let debugLog = image.parserDebugLog {
                report += "**Parser Debug Log:**\n"
                report += "```\n"
                report += debugLog
                report += "\n```\n\n"
            }

            report += "---\n\n"
        }

        return report
    }
}
