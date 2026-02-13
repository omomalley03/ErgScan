import Foundation
import Combine
import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Scanning State

enum ScanningState: Equatable {
    case ready          // Ready to start scanning
    case capturing      // Actively capturing and processing
    case locked(RecognizedTable)
    case saved

    static func == (lhs: ScanningState, rhs: ScanningState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.capturing, .capturing), (.saved, .saved):
            return true
        case (.locked(let lTable), .locked(let rTable)):
            return lTable.stableHash == rTable.stableHash
        default:
            return false
        }
    }
}

@MainActor
class ScannerViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var state: ScanningState = .ready
    @Published var completenessScore: Double = 0.0
    @Published var fieldProgress: Double = 0.0  // Field-based progress (0.0 - 1.0)
    @Published var currentTable: RecognizedTable?
    @Published var errorMessage: String?
    @Published var captureCount: Int = 0

    // Debug properties (only computed when showDebugTabs is true)
    @Published var debugResults: [GuideRelativeOCRResult] = []
    @Published var parserDebugLog: String = ""
    @Published var allCapturesLog: String = ""  // Combined logs from all 3 captures

    // MARK: - Services

    let cameraService = CameraService()
    private let visionService = VisionService()
    private let tableParser = TableParserService()
    private let hapticService = HapticService()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Scanning State

    private var hasTriggeredHaptic = false
    private var accumulatedTable: RecognizedTable?  // Accumulate best data across scans

    // Benchmark tracking: save all captured images for ground truth dataset
    private var capturedImagesForBenchmark: [UIImage] = []
    private var capturedOCRResultsForBenchmark: [(ocrResults: [GuideRelativeOCRResult], parsedTable: RecognizedTable, debugLog: String)] = []

    // Performance optimization: only compute debug info when needed
    @AppStorage("showDebugTabs") private var showDebugTabs = true  // Temporarily enabled for debugging

    init() {
        // Forward cameraService changes so the view re-renders
        // when isSessionRunning changes
        cameraService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Camera Setup

    func setupCamera() async {
        do {
            print("🎥 Setting up camera...")
            let authorized = await cameraService.requestCameraPermission()
            guard authorized else {
                errorMessage = "Camera permission denied. Please enable in Settings."
                return
            }

            try await cameraService.setupCamera()
            print("📹 Camera setup complete")

            cameraService.startSession()
            hapticService.prepare()
            print("🚀 Camera session started, ready to scan")

        } catch {
            print("❌ Camera setup error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        cameraService.stopSession()
    }

    // MARK: - Iterative Scanning

    func startScanning() async {
        state = .capturing
        captureCount = 0
        hasTriggeredHaptic = false
        accumulatedTable = nil  // Reset accumulated data for new scan
        allCapturesLog = ""  // Reset combined log

        print("🚀 Starting 3-photo capture for benchmark...")

        var combinedLog = "======================================\n"
        combinedLog += "VARIABLE INTERVALS DEBUG LOG\n"
        combinedLog += "3-Photo Capture Session\n"
        combinedLog += "======================================\n\n"

        // Capture exactly 3 photos for benchmark testing
        for i in 1...3 {
            captureCount = i
            print("📸 Capture \(i) of 3")

            await captureAndProcess()

            // Append this capture's log
            if i - 1 < capturedOCRResultsForBenchmark.count {
                let captureLog = capturedOCRResultsForBenchmark[i - 1].debugLog
                combinedLog += "========== CAPTURE \(i) OF 3 ==========\n\n"
                combinedLog += captureLog
                combinedLog += "\n\n"
            }

            // Wait between captures (allow user to adjust framing if needed)
            if i < 3 {
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            }
        }

        // Add final merged result summary
        if let finalTable = accumulatedTable {
            combinedLog += "======================================\n"
            combinedLog += "FINAL MERGED RESULT\n"
            combinedLog += "======================================\n"
            combinedLog += "Workout Type: \(finalTable.workoutType ?? "nil")\n"
            combinedLog += "Category: \(finalTable.category?.rawValue ?? "nil")\n"
            combinedLog += "Is Variable Interval: \(finalTable.isVariableInterval ?? false)\n"
            combinedLog += "Description: \(finalTable.description ?? "nil")\n"
            combinedLog += "Reps: \(finalTable.reps ?? 0)\n"
            combinedLog += "Work Per Rep: \(finalTable.workPerRep ?? "nil")\n"
            combinedLog += "Rest Per Rep: \(finalTable.restPerRep ?? "nil")\n"
            combinedLog += "Data Rows Parsed: \(finalTable.rows.count)\n"
            combinedLog += "======================================\n"
        }

        allCapturesLog = combinedLog

        // After 3 captures, export benchmark data with verbose logs
        exportBenchmarkToFiles()

        // Auto-lock after 3 captures with the accumulated table
        if let table = accumulatedTable {
            handleLocking(table: table)
        }
    }

    private func captureAndProcess() async {
        // Capture photo
        guard let fullImage = await cameraService.capturePhoto(),
              let fullCG = fullImage.cgImage else {
            print("❌ Failed to capture photo")
            return
        }

        // Crop to center square
        let side = min(fullCG.width, fullCG.height)
        let cropRect = CGRect(
            x: (fullCG.width - side) / 2,
            y: (fullCG.height - side) / 2,
            width: side,
            height: side
        )

        guard let croppedCG = fullCG.cropping(to: cropRect) else {
            print("❌ Failed to crop photo")
            return
        }

        let croppedImage = UIImage(cgImage: croppedCG, scale: fullImage.scale, orientation: fullImage.imageOrientation)

        // Save captured image for benchmark dataset
        capturedImagesForBenchmark.append(croppedImage)

        // Run OCR
        do {
            let ocrResults = try await visionService.recognizeText(in: croppedImage)
            print("✅ OCR found \(ocrResults.count) results")

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

            // Parse the table
            let parseResult = tableParser.parseTable(from: guideRelativeResults)
            let newTable = parseResult.table

            // Merge with accumulated table (preserve good data from previous scans)
            let mergedTable = mergeTable(existing: accumulatedTable, new: newTable)
            accumulatedTable = mergedTable

            // Save OCR results for benchmark dataset
            capturedOCRResultsForBenchmark.append((guideRelativeResults, mergedTable, parseResult.debugLog))

            // Update published properties
            currentTable = mergedTable
            completenessScore = mergedTable.completenessScore
            fieldProgress = calculateFieldProgress(mergedTable)
            print("📊 Field Progress: \(Int(fieldProgress * 100))% | WorkoutType: \(mergedTable.workoutType ?? "nil") | Rows: \(mergedTable.rows.count)")

            // Update debug info if enabled
            if showDebugTabs {
                debugResults = guideRelativeResults
                parserDebugLog = parseResult.debugLog
            }

            // Check if complete (all splits have their essential data)
            if isTableReadyToLock(mergedTable) {
                handleLocking(table: mergedTable)
            }

        } catch {
            print("⚠️ OCR error: \(error)")
        }
    }

    private func handleLocking(table: RecognizedTable) {
        guard !hasTriggeredHaptic else { return }

        // Trigger haptic feedback
        hapticService.triggerSuccess()
        hasTriggeredHaptic = true

        // Transition to locked state
        state = .locked(table)
        print("✅ Workout locked!")
    }

    // MARK: - Retake

    func retake() {
        // Reset state
        state = .ready
        currentTable = nil
        accumulatedTable = nil
        completenessScore = 0.0
        fieldProgress = 0.0
        captureCount = 0
        debugResults = []
        parserDebugLog = ""
        allCapturesLog = ""  // Clear combined log
        hasTriggeredHaptic = false
        capturedImagesForBenchmark = []  // Clear benchmark images
        capturedOCRResultsForBenchmark = []  // Clear OCR results
        print("🔄 Reset to ready state")
    }

    // MARK: - Save Workout

    func saveWorkout(context: ModelContext) async {
        guard case .locked(let table) = state else { return }

        // 1. Save production workout
        // TODO: Implement production workout saving logic (Workout + Intervals)

        // 2. Save benchmark dataset
        saveBenchmarkDataset(table: table, context: context)

        state = .saved
    }

    private func saveBenchmarkDataset(table: RecognizedTable, context: ModelContext) {
        print("💾 Saving benchmark dataset with \(capturedImagesForBenchmark.count) images")

        // Create BenchmarkWorkout with ground truth from locked table
        let benchmarkWorkout = BenchmarkWorkout(
            workoutType: table.workoutType,
            category: table.category,
            workoutDescription: table.description,
            totalTime: table.totalTime,
            totalDistance: table.totalDistance,
            date: table.date,
            reps: table.reps,
            workPerRep: table.workPerRep,
            restPerRep: table.restPerRep
        )
        context.insert(benchmarkWorkout)

        // Create BenchmarkIntervals from table rows
        for (index, row) in table.rows.enumerated() {
            let benchmarkInterval = BenchmarkInterval(
                orderIndex: index,
                time: row.time?.text,
                meters: Int(row.meters?.text ?? "0"),
                splitPer500m: row.splitPer500m?.text,
                strokeRate: Int(row.strokeRate?.text ?? "0"),
                heartRate: Int(row.heartRate?.text ?? "0")
            )
            benchmarkInterval.workout = benchmarkWorkout
            context.insert(benchmarkInterval)
        }

        // Create BenchmarkImages for all captured photos
        for (index, image) in capturedImagesForBenchmark.enumerated() {
            // Compress image to JPEG at 0.8 quality
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("⚠️ Failed to compress image \(index + 1)")
                continue
            }

            let benchmarkImage = BenchmarkImage(
                imageData: imageData,
                angleDescription: "Capture \(index + 1) of \(capturedImagesForBenchmark.count)",
                resolution: "\(Int(image.size.width))x\(Int(image.size.height))"
            )

            // Save initial OCR results
            if index < capturedOCRResultsForBenchmark.count {
                let ocrData = capturedOCRResultsForBenchmark[index]
                benchmarkImage.rawOCRResults = try? JSONEncoder().encode(ocrData.ocrResults)
                benchmarkImage.parsedTable = try? JSONEncoder().encode(ocrData.parsedTable)
                benchmarkImage.ocrConfidence = ocrData.parsedTable.averageConfidence
                benchmarkImage.parserDebugLog = ocrData.debugLog
            }

            benchmarkImage.workout = benchmarkWorkout
            context.insert(benchmarkImage)
        }

        // Save context
        do {
            try context.save()
            print("✅ Benchmark dataset saved successfully")
        } catch {
            print("❌ Error saving benchmark dataset: \(error)")
        }

        // Clear captured images
        capturedImagesForBenchmark = []
    }

    // MARK: - Benchmark Export

    private func exportBenchmarkToFiles() {
        print("📤 Exporting benchmark data to files...")

        // Create benchmark directory in Documents
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access documents directory")
            return
        }

        let benchmarkURL = documentsURL.appendingPathComponent("Benchmarks")
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sessionURL = benchmarkURL.appendingPathComponent("session_\(timestamp)")

        // Create session directory
        do {
            try fileManager.createDirectory(at: sessionURL, withIntermediateDirectories: true)
            print("✅ Created benchmark directory: \(sessionURL.path)")
        } catch {
            print("❌ Failed to create benchmark directory: \(error)")
            return
        }

        // Save each captured image and its OCR data
        for (index, image) in capturedImagesForBenchmark.enumerated() {
            let captureNum = index + 1

            // Save image as PNG
            if let imageData = image.pngData() {
                let imageURL = sessionURL.appendingPathComponent("capture_\(captureNum).png")
                do {
                    try imageData.write(to: imageURL)
                    print("✅ Saved image \(captureNum): \(imageURL.lastPathComponent)")
                } catch {
                    print("❌ Failed to save image \(captureNum): \(error)")
                }
            }

            // Save verbose OCR and parser data
            if index < capturedOCRResultsForBenchmark.count {
                let ocrData = capturedOCRResultsForBenchmark[index]

                // Save parser debug log (most important for debugging)
                let logURL = sessionURL.appendingPathComponent("capture_\(captureNum)_parser_log.txt")
                do {
                    try ocrData.debugLog.write(to: logURL, atomically: true, encoding: .utf8)
                    print("✅ Saved parser log \(captureNum): \(logURL.lastPathComponent)")
                } catch {
                    print("❌ Failed to save parser log \(captureNum): \(error)")
                }

                // Save parsed table as JSON
                let tableURL = sessionURL.appendingPathComponent("capture_\(captureNum)_parsed_table.json")
                if let tableData = try? JSONEncoder().encode(ocrData.parsedTable),
                   let jsonString = String(data: tableData, encoding: .utf8) {
                    do {
                        try jsonString.write(to: tableURL, atomically: true, encoding: .utf8)
                        print("✅ Saved parsed table \(captureNum): \(tableURL.lastPathComponent)")
                    } catch {
                        print("❌ Failed to save parsed table \(captureNum): \(error)")
                    }
                }

                // Save raw OCR results as JSON
                let ocrURL = sessionURL.appendingPathComponent("capture_\(captureNum)_ocr_results.json")
                if let ocrResultsData = try? JSONEncoder().encode(ocrData.ocrResults),
                   let jsonString = String(data: ocrResultsData, encoding: .utf8) {
                    do {
                        try jsonString.write(to: ocrURL, atomically: true, encoding: .utf8)
                        print("✅ Saved OCR results \(captureNum): \(ocrURL.lastPathComponent)")
                    } catch {
                        print("❌ Failed to save OCR results \(captureNum): \(error)")
                    }
                }
            }
        }

        // Save merged/final table
        if let finalTable = accumulatedTable {
            let finalTableURL = sessionURL.appendingPathComponent("final_merged_table.json")
            if let tableData = try? JSONEncoder().encode(finalTable),
               let jsonString = String(data: tableData, encoding: .utf8) {
                do {
                    try jsonString.write(to: finalTableURL, atomically: true, encoding: .utf8)
                    print("✅ Saved final merged table")
                } catch {
                    print("❌ Failed to save final merged table: \(error)")
                }
            }
        }

        // Save summary report
        var summaryReport = """
        ======================================
        BENCHMARK SESSION REPORT
        ======================================
        Timestamp: \(timestamp)
        Captures: \(capturedImagesForBenchmark.count)
        Session Directory: \(sessionURL.path)

        """

        for (index, ocrData) in capturedOCRResultsForBenchmark.enumerated() {
            let captureNum = index + 1
            summaryReport += """

            --- Capture \(captureNum) ---
            OCR Results: \(ocrData.ocrResults.count)
            Workout Type: \(ocrData.parsedTable.workoutType ?? "nil")
            Category: \(ocrData.parsedTable.category?.rawValue ?? "nil")
            Is Variable Interval: \(ocrData.parsedTable.isVariableInterval ?? false)
            Reps: \(ocrData.parsedTable.reps ?? 0)
            Data Rows: \(ocrData.parsedTable.rows.count)
            Confidence: \(String(format: "%.1f%%", ocrData.parsedTable.averageConfidence * 100))
            Completeness: \(String(format: "%.1f%%", ocrData.parsedTable.completenessScore * 100))

            """
        }

        if let finalTable = accumulatedTable {
            summaryReport += """

            ======================================
            FINAL MERGED RESULT
            ======================================
            Workout Type: \(finalTable.workoutType ?? "nil")
            Category: \(finalTable.category?.rawValue ?? "nil")
            Is Variable Interval: \(finalTable.isVariableInterval ?? false)
            Description: \(finalTable.description ?? "nil")
            Reps: \(finalTable.reps ?? 0)
            Work Per Rep: \(finalTable.workPerRep ?? "nil")
            Rest Per Rep: \(finalTable.restPerRep ?? "nil")
            Total Time: \(finalTable.totalTime ?? "nil")
            Total Distance: \(finalTable.totalDistance ?? 0)
            Data Rows: \(finalTable.rows.count)
            Average Confidence: \(String(format: "%.1f%%", finalTable.averageConfidence * 100))
            Completeness Score: \(String(format: "%.1f%%", finalTable.completenessScore * 100))

            """
        }

        summaryReport += """
        ======================================
        END OF REPORT
        ======================================
        """

        let summaryURL = sessionURL.appendingPathComponent("SUMMARY.txt")
        do {
            try summaryReport.write(to: summaryURL, atomically: true, encoding: .utf8)
            print("✅ Saved summary report")
            print("📂 Benchmark saved to: \(sessionURL.path)")
        } catch {
            print("❌ Failed to save summary report: \(error)")
        }
    }

    // MARK: - Field Editing

    func updateField(in table: inout RecognizedTable, field: String, value: String) {
        // Update the specified field in the table
        switch field {
        case "workoutType":
            table.workoutType = value
        case "description":
            table.description = value
        case "totalTime":
            table.totalTime = value
        case "totalDistance":
            table.totalDistance = Int(value)
        default:
            break
        }

        // Update locked state with modified table
        state = .locked(table)
    }

    // MARK: - Data Accumulation

    /// Merge two tables, preferring non-nil values and higher confidence
    private func mergeTable(existing: RecognizedTable?, new: RecognizedTable) -> RecognizedTable {
        guard let existing = existing else {
            return new
        }

        return RecognizedTable(
            workoutType: new.workoutType ?? existing.workoutType,
            category: new.category ?? existing.category,
            date: new.date ?? existing.date,
            totalTime: new.totalTime ?? existing.totalTime,
            description: new.description ?? existing.description,
            reps: new.reps ?? existing.reps,
            workPerRep: new.workPerRep ?? existing.workPerRep,
            restPerRep: new.restPerRep ?? existing.restPerRep,
            totalDistance: new.totalDistance ?? existing.totalDistance,
            averages: mergeRow(existing: existing.averages, new: new.averages),
            rows: mergeRows(existing: existing.rows, new: new.rows),
            averageConfidence: max(existing.averageConfidence, new.averageConfidence)
        )
    }

    /// Merge two rows, preferring non-nil values and higher confidence
    private func mergeRow(existing: TableRow?, new: TableRow?) -> TableRow? {
        guard let existing = existing else { return new }
        guard let new = new else { return existing }

        var merged = TableRow(boundingBox: new.boundingBox)
        merged.time = mergeCellValue(existing: existing.time, new: new.time)
        merged.meters = mergeCellValue(existing: existing.meters, new: new.meters)
        merged.splitPer500m = mergeCellValue(existing: existing.splitPer500m, new: new.splitPer500m)
        merged.strokeRate = mergeCellValue(existing: existing.strokeRate, new: new.strokeRate)
        merged.heartRate = mergeCellValue(existing: existing.heartRate, new: new.heartRate)
        return merged
    }

    /// Merge rows arrays, aligning by index and merging individual rows
    private func mergeRows(existing: [TableRow], new: [TableRow]) -> [TableRow] {
        let maxCount = max(existing.count, new.count)
        var merged: [TableRow] = []

        for i in 0..<maxCount {
            let existingRow = i < existing.count ? existing[i] : nil
            let newRow = i < new.count ? new[i] : nil

            if let mergedRow = mergeRow(existing: existingRow, new: newRow) {
                merged.append(mergedRow)
            }
        }

        return merged
    }

    /// Merge individual cell values, preferring non-nil and higher confidence
    private func mergeCellValue(existing: OCRResult?, new: OCRResult?) -> OCRResult? {
        guard let existing = existing else { return new }
        guard let new = new else { return existing }

        // Prefer higher confidence value
        return new.confidence > existing.confidence ? new : existing
    }

    /// Check if table is ready to lock (all splits have essential data)
    private func isTableReadyToLock(_ table: RecognizedTable) -> Bool {
        // Must have workout type
        guard table.workoutType != nil else {
            print("⏳ Not ready: Missing workout type")
            return false
        }

        // Must have averages with all 4 essential fields: time, meters, split, rate
        guard let averages = table.averages,
              averages.time != nil,
              averages.meters != nil,
              averages.splitPer500m != nil,
              averages.strokeRate != nil else {
            print("⏳ Not ready: Missing averages (need all 4 fields: time, meters, split, rate)")
            return false
        }

        // If there are data rows, check essential fields
        if !table.rows.isEmpty {
            // All rows must have: time, meters, split
            let allRowsHaveEssentials = table.rows.allSatisfy { row in
                row.time != nil && row.meters != nil && row.splitPer500m != nil
            }

            guard allRowsHaveEssentials else {
                let completeCount = table.rows.filter { row in
                    row.time != nil && row.meters != nil && row.splitPer500m != nil
                }.count
                print("⏳ Not ready: Only \(completeCount)/\(table.rows.count) rows have time/meters/split")
                return false
            }

            // All rows except the last must have stroke rate
            if table.rows.count > 1 {
                let allButLastHaveRate = table.rows.dropLast().allSatisfy { row in
                    row.strokeRate != nil
                }

                guard allButLastHaveRate else {
                    let rateCount = table.rows.filter { $0.strokeRate != nil }.count
                    print("⏳ Not ready: Only \(rateCount)/\(table.rows.count) rows have stroke rate")
                    return false
                }
            }

            // Last row: stroke rate required if distance >= 100m
            if let lastRow = table.rows.last, lastRow.strokeRate == nil {
                let lastRowMeters = Int(lastRow.meters?.text.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
                if lastRowMeters >= 100 {
                    print("⏳ Not ready: Last row has \(lastRowMeters)m but no stroke rate (required for >= 100m)")
                    return false
                }
            }
        }

        print("✅ Ready to lock: All essential data present")
        return true
    }

    /// Calculate field-based progress (0.0 - 1.0) based on actual filled fields
    func calculateFieldProgress(_ table: RecognizedTable?) -> Double {
        guard let table = table else { return 0.0 }

        var filledFields = 0
        var totalFields = 0

        // Averages row (4 fields)
        totalFields += 4
        if let avg = table.averages {
            if avg.time != nil { filledFields += 1 }
            if avg.meters != nil { filledFields += 1 }
            if avg.splitPer500m != nil { filledFields += 1 }
            if avg.strokeRate != nil { filledFields += 1 }
        }

        // Data rows (4 fields each, but last row's stroke rate is optional)
        if !table.rows.isEmpty {
            // Each row: time, meters, split, rate (but rate optional on last row)
            for (index, row) in table.rows.enumerated() {
                let isLastRow = index == table.rows.count - 1

                // Always count these 3 fields
                totalFields += 3
                if row.time != nil { filledFields += 1 }
                if row.meters != nil { filledFields += 1 }
                if row.splitPer500m != nil { filledFields += 1 }

                // Stroke rate: count for all rows except last
                if !isLastRow {
                    totalFields += 1
                    if row.strokeRate != nil { filledFields += 1 }
                } else {
                    // Last row: only count rate if it exists
                    if row.strokeRate != nil {
                        totalFields += 1
                        filledFields += 1
                    }
                }
            }
        } else {
            // Default to 20 fields (5 rows × 4) when we don't know row count yet
            totalFields += 20
        }

        return totalFields > 0 ? Double(filledFields) / Double(totalFields) : 0.0
    }
}
