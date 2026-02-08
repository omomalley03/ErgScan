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

    // MARK: - Services

    let cameraService = CameraService()
    private let visionService = VisionService()
    private let tableParser = TableParserService()
    private let hapticService = HapticService()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Scanning State

    private var hasTriggeredHaptic = false
    private var accumulatedTable: RecognizedTable?  // Accumulate best data across scans

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

        print("🚀 Starting iterative scanning...")

        // Iteratively capture until complete (no limit on attempts)
        while state == .capturing {
            captureCount += 1
            print("📸 Capture attempt \(captureCount)")

            await captureAndProcess()

            // Check if we should stop
            if case .locked = state {
                print("🔒 Locked with complete data")
                break
            }

            // Wait a moment before next capture (allow user to adjust framing)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
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
        hasTriggeredHaptic = false
        print("🔄 Reset to ready state")
    }

    // MARK: - Save Workout

    func saveWorkout(context: ModelContext) async {
        guard case .locked = state else { return }

        // Create workout model and save
        // TODO: Implement workout saving logic

        state = .saved
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
