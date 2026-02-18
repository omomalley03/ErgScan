import Foundation
import Combine
import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Scanning State

enum ScanningState: Equatable {
    case ready          // Ready to start scanning
    case capturing      // Actively capturing and processing
    case incompletePrompt(RecognizedTable, firstScan: Bool)  // Data meets locking criteria but is incomplete
    case manualInput(RecognizedTable?)  // Fallback to manual input after 6 failed scans
    case locked(RecognizedTable)
    case saved

    static func == (lhs: ScanningState, rhs: ScanningState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.capturing, .capturing), (.saved, .saved):
            return true
        case (.incompletePrompt(let lTable, let lFirst), .incompletePrompt(let rTable, let rFirst)):
            return lTable.stableHash == rTable.stableHash && lFirst == rFirst
        case (.manualInput(let lTable), .manualInput(let rTable)):
            return lTable?.stableHash == rTable?.stableHash
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
    @Published var shouldValidateOnLoad: Bool = false  // Auto-validate in ManualDataEntryView when scan fails validation
    @Published var detectedPRs: [(duration: Double, watts: Double)] = []

    // User for linking workouts to accounts
    @Published var currentUser: User?

    // Debug properties (only computed when showDebugTabs is true)
    @Published var debugResults: [GuideRelativeOCRResult] = []
    @Published var parserDebugLog: String = ""

    // MARK: - Services

    let cameraService: CameraService
    private let visionService = VisionService()
    private let tableParser = TableParserService()
    private let hapticService = HapticService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Scanning State

    private var hasTriggeredHaptic = false
    private var accumulatedTable: RecognizedTable?  // Accumulate best data across scans
    private var previousScreenTable: RecognizedTable?  // Saved data from previous screen(s) for multi-screen merge

    // Benchmark tracking: save all captured images for ground truth dataset
    private var capturedImagesForBenchmark: [UIImage] = []
    private var capturedOCRResultsForBenchmark: [(ocrResults: [GuideRelativeOCRResult], parsedTable: RecognizedTable, debugLog: String)] = []

    // Performance optimization: only compute debug info when needed
    @AppStorage("showDebugTabs") private var showDebugTabs = false

    init(cameraService: CameraService) {
        self.cameraService = cameraService
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
            // Skip permission + config if already pre-warmed
            if !cameraService.isConfigured {
                print("🎥 Setting up camera...")
                let authorized = await cameraService.requestCameraPermission()
                guard authorized else {
                    errorMessage = "Camera permission denied. Please enable in Settings."
                    return
                }

                try await cameraService.setupCamera()
                print("📹 Camera setup complete")
            } else {
                print("⚡ Camera pre-warmed, starting session directly")
            }

            // Start session with retry — camera hardware may still be releasing from a previous session
            for attempt in 1...3 {
                cameraService.startSession()
                // Wait for the session to actually start (startSession confirms asynchronously)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

                if cameraService.isSessionRunning {
                    print("🚀 Camera session started on attempt \(attempt)")
                    break
                }
                if attempt < 3 {
                    print("⚠️ Camera session not running after attempt \(attempt), retrying...")
                }
            }

            if !cameraService.isSessionRunning {
                print("❌ Camera session failed to start after 3 attempts")
                errorMessage = "Camera failed to start. Please try again."
            }

            hapticService.prepare()

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
        previousScreenTable = nil  // Reset multi-screen data

        print("🚀 Starting iterative scanning...")

        // Iteratively capture until complete or hit 6-scan fallback
        while state == .capturing {
            captureCount += 1
            print("📸 Capture attempt \(captureCount)")

            await captureAndProcess()

            // Check if we should stop
            if case .locked = state {
                print("🔒 Locked with complete data")
                break
            }

            // Fallback: after 4 scans without locking, offer manual input
            if captureCount >= 4 {
                print("⚠️ Reached 4 scans without locking - triggering manual input fallback")
                shouldValidateOnLoad = false  // Don't auto-validate for 4-scan fallback
                state = .manualInput(accumulatedTable)
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

        // Save captured image for benchmark dataset
        capturedImagesForBenchmark.append(croppedImage)

        // Run OCR
        do {
            let ocrResults = try await visionService.recognizeText(in: croppedImage)
            print("✅ OCR found \(ocrResults.count) results")

            // Convert to guide-relative coordinates.
            // Vision returns normalized coords with y=0 at the bottom (display-oriented
            // because VisionService now passes the actual image orientation).
            // Flip y to match UIKit's top-down convention used by the parser.
            let guideRelativeResults = ocrResults.map { result in
                let box = result.boundingBox
                let guideBox = CGRect(
                    x: box.origin.x,
                    y: 1 - box.origin.y - box.height,
                    width: box.width,
                    height: box.height
                )
                return GuideRelativeOCRResult(
                    original: result,
                    guideRelativeBox: guideBox
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

        // If we have data from a previous screen, merge it in
        var finalTable = table
        if let prevScreen = previousScreenTable {
            let mergedRows = mergeScreenRows(
                firstScreen: prevScreen.rows,
                secondScreen: table.rows,
                category: table.category ?? prevScreen.category
            )
            finalTable = RecognizedTable(
                workoutType: table.workoutType ?? prevScreen.workoutType,
                category: table.category ?? prevScreen.category,
                date: table.date ?? prevScreen.date,
                totalTime: table.totalTime ?? prevScreen.totalTime,
                description: table.description ?? prevScreen.description,
                reps: table.reps ?? prevScreen.reps,
                workPerRep: table.workPerRep ?? prevScreen.workPerRep,
                restPerRep: table.restPerRep ?? prevScreen.restPerRep,
                isVariableInterval: table.isVariableInterval ?? prevScreen.isVariableInterval,
                totalDistance: table.totalDistance ?? prevScreen.totalDistance,
                averages: mergeRow(existing: prevScreen.averages, new: table.averages),
                rows: mergedRows,
                averageConfidence: max(prevScreen.averageConfidence, table.averageConfidence)
            )
            print("📊 Merged with previous screen: \(prevScreen.rows.count) + \(table.rows.count) → \(mergedRows.count) rows")
        }

        // Check if data is complete
        let completenessCheck = finalTable.checkDataCompleteness()
        let isFirstScan = previousScreenTable == nil

        if completenessCheck.isComplete {
            // Run validation checks (split accuracy + consistency)
            if validateScanData(finalTable) {
                // All checks pass — lock normally
                hapticService.triggerSuccess()
                hasTriggeredHaptic = true
                state = .locked(finalTable)
                previousScreenTable = nil
                print("✅ Workout locked with complete data! (\(finalTable.rows.count) rows)")
            } else {
                // Validation failed — send to manual input for correction
                print("⚠️ Scan data has validation errors, redirecting to manual input")
                shouldValidateOnLoad = true
                state = .manualInput(finalTable)  // pre-populated with scanned data
            }
        } else {
            // Data meets locking criteria but is incomplete
            state = .incompletePrompt(finalTable, firstScan: isFirstScan)
            print("⚠️ Workout meets locking criteria but data appears incomplete")
            if let reason = completenessCheck.reason {
                print("   Reason: \(reason)")
            }
        }
    }

    // MARK: - Scan Data Validation

    /// Validate scanned data for split accuracy and consistency
    /// Returns true if all checks pass, false if there are validation errors
    private func validateScanData(_ table: RecognizedTable) -> Bool {
        // Determine workout sub-type
        let isInterval = table.category == .interval
        let isDistanceBased = !isInterval &&
            (table.workoutType?.range(of: "^\\d{3,5}m$", options: .regularExpression) != nil)

        // 1. Split accuracy check
        for i in 0..<table.rows.count {
            let row = table.rows[i]
            guard let timeStr = row.time?.text,
                  let metersStr = row.meters?.text,
                  let splitStr = row.splitPer500m?.text,
                  let time = PowerCurveService.timeStringToSeconds(timeStr),
                  let actualSplit = PowerCurveService.timeStringToSeconds(splitStr) else { continue }
            let meters = Double(metersStr.replacingOccurrences(of: ",", with: "")) ?? 0
            guard meters > 0, time > 0 else { continue }

            var expectedSplit: Double
            if isInterval {
                expectedSplit = (time / meters) * 500.0
            } else if isDistanceBased {
                let prevMeters: Double = i > 0
                    ? (Double((table.rows[i-1].meters?.text ?? "0").replacingOccurrences(of: ",", with: "")) ?? 0)
                    : 0
                let effective = meters - prevMeters
                guard effective > 0 else { continue }
                expectedSplit = (time / effective) * 500.0
            } else {
                // Single time: cumulative time, per-split meters
                let prevTime: Double = i > 0
                    ? (PowerCurveService.timeStringToSeconds(table.rows[i-1].time?.text ?? "") ?? 0)
                    : 0
                let effective = time - prevTime
                guard effective > 0 else { continue }
                expectedSplit = (effective / meters) * 500.0
            }

            let floored = floor(expectedSplit * 10.0) / 10.0
            if abs(floored - actualSplit) > 0.1 {
                print("⚠️ Split accuracy error at row \(i): expected \(floored), actual \(actualSplit)")
                return false  // Split mismatch
            }
        }

        // 2. Split consistency check (single workouts only)
        if !isInterval && table.rows.count >= 2 {
            let parseM = { (text: String?) -> Double? in
                guard let t = text else { return nil }
                return Double(t.replacingOccurrences(of: ",", with: ""))
            }
            if isDistanceBased {
                // Single Distance: check meter gaps (cumulative meters)
                guard let firstMeters = parseM(table.rows[0].meters?.text), firstMeters > 0 else { return true }
                for i in 1..<(table.rows.count - 1) {
                    guard let current = parseM(table.rows[i].meters?.text),
                          let prev = parseM(table.rows[i-1].meters?.text) else { continue }
                    if abs((current - prev) - firstMeters) > 1 {
                        print("⚠️ Split consistency error at row \(i): gap \(current - prev) ≠ expected \(firstMeters)")
                        return false
                    }
                }
            } else {
                // Single Time: check time gaps (cumulative time)
                guard let firstTime = PowerCurveService.timeStringToSeconds(table.rows[0].time?.text ?? ""),
                      firstTime > 0 else { return true }
                for i in 1..<(table.rows.count - 1) {
                    guard let current = PowerCurveService.timeStringToSeconds(table.rows[i].time?.text ?? ""),
                          let prev = PowerCurveService.timeStringToSeconds(table.rows[i-1].time?.text ?? "") else { continue }
                    if abs((current - prev) - firstTime) > 1 {
                        print("⚠️ Split consistency error at row \(i): time gap \(current - prev) ≠ expected \(firstTime)")
                        return false
                    }
                }
            }
        }

        // 3. Meters completeness (already checked by checkDataCompleteness — skip)
        return true
    }

    // MARK: - Multi-Screen Scanning

    func continueScanning() async {
        guard case .incompletePrompt(let firstScreenTable, _) = state else { return }

        // Save first screen data, then start a fresh scan for the second screen
        previousScreenTable = firstScreenTable
        accumulatedTable = nil
        hasTriggeredHaptic = false
        captureCount = 0
        state = .capturing

        print("🔄 Starting fresh scan for next screen...")
        print("   Previous screen rows: \(firstScreenTable.rows.count)")

        // Run a full scan cycle for the new screen
        while state == .capturing {
            captureCount += 1
            print("📸 Next-screen capture attempt \(captureCount)")

            await captureAndProcess()

            if case .locked = state {
                break
            }
            if case .incompletePrompt = state {
                break
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func retryScan() {
        guard case .incompletePrompt = state else { return }

        // Restart the scanning process from scratch
        print("🔄 User requested retry - restarting scan")
        retake()
    }

    func acceptIncompleteData() {
        guard case .incompletePrompt(let table, _) = state else { return }

        // Send to manual edit so user can fill in missing data
        shouldValidateOnLoad = true
        state = .manualInput(table)
        previousScreenTable = nil

        print("⚠️ User chose to manually edit incomplete data")
        print("   Rows: \(table.rows.count)")
    }

    // MARK: - Retake

    func retake() {
        // Reset state
        state = .ready
        currentTable = nil
        accumulatedTable = nil
        previousScreenTable = nil
        completenessScore = 0.0
        fieldProgress = 0.0
        captureCount = 0
        debugResults = []
        parserDebugLog = ""
        hasTriggeredHaptic = false
        capturedImagesForBenchmark = []  // Clear benchmark images
        capturedOCRResultsForBenchmark = []  // Clear OCR results
        print("🔄 Reset to ready state")
    }

    // MARK: - Save Workout

    func saveWorkout(
        context: ModelContext,
        customDate: Date? = nil,
        intensityZone: IntensityZone? = nil,
        isErgTest: Bool = false,
        privacy: String = WorkoutPrivacy.friends.rawValue,
        scanOnBehalfOfUserID: String? = nil,
        scanOnBehalfOfUsername: String? = nil
    ) async -> Workout? {
        guard case .locked(let table) = state else { return nil }

        // Require authenticated user
        guard let currentUser = self.currentUser else {
            print("❌ Cannot save workout: No authenticated user")
            errorMessage = "Must be signed in to save workouts"
            return nil
        }

        print("💾 Saving workout to user log for user: \(currentUser.appleUserID)")

        // Get last captured image
        let lastImage = capturedImagesForBenchmark.last
        let imageData = lastImage?.jpegData(compressionQuality: 0.8)

        // Use custom date if provided, otherwise fall back to table.date or today
        let workoutDate = customDate ?? table.date ?? Date()

        // Create Workout
        let workout = Workout(
            date: workoutDate,
            workoutType: table.workoutType ?? "Unknown",
            category: table.category ?? .single,
            totalTime: table.totalTime ?? "",
            totalDistance: table.totalDistance,
            ocrConfidence: table.averageConfidence,
            imageData: imageData,
            intensityZone: intensityZone?.rawValue,
            isErgTest: isErgTest
        )

        // Link to user
        workout.user = currentUser
        workout.userID = currentUser.appleUserID
        workout.syncedToCloud = true
        workout.sharePrivacy = privacy

        // Mark if scanned on behalf of another rower
        workout.scannedForUserID = scanOnBehalfOfUserID
        workout.scannedForUsername = scanOnBehalfOfUsername

        context.insert(workout)

        // Save averages/summary row as interval with orderIndex = 0
        if let averages = table.averages {
            let averagesInterval = Interval(
                orderIndex: 0,
                time: averages.time?.text ?? "",
                meters: averages.meters?.text ?? "",
                splitPer500m: averages.splitPer500m?.text ?? "",
                strokeRate: averages.strokeRate?.text ?? "",
                heartRate: averages.heartRate?.text,
                timeConfidence: Double(averages.time?.confidence ?? 0),
                metersConfidence: Double(averages.meters?.confidence ?? 0),
                splitConfidence: Double(averages.splitPer500m?.confidence ?? 0),
                rateConfidence: Double(averages.strokeRate?.confidence ?? 0),
                heartRateConfidence: Double(averages.heartRate?.confidence ?? 0)
            )
            averagesInterval.workout = workout
            context.insert(averagesInterval)
        }

        // Create Intervals from data rows (starting at orderIndex = 1)
        for (index, row) in table.rows.enumerated() {
            let interval = Interval(
                orderIndex: index + 1,
                time: row.time?.text ?? "",
                meters: row.meters?.text ?? "",
                splitPer500m: row.splitPer500m?.text ?? "",
                strokeRate: row.strokeRate?.text ?? "",
                heartRate: row.heartRate?.text,
                timeConfidence: Double(row.time?.confidence ?? 0),
                metersConfidence: Double(row.meters?.confidence ?? 0),
                splitConfidence: Double(row.splitPer500m?.confidence ?? 0),
                rateConfidence: Double(row.strokeRate?.confidence ?? 0),
                heartRateConfidence: Double(row.heartRate?.confidence ?? 0)
            )
            interval.workout = workout
            context.insert(interval)
        }

        // Save context
        do {
            try context.save()
            print("✅ Workout saved successfully")

            // Detect power curve PRs
            let userID = currentUser.appleUserID
            let userWorkouts = try context.fetch(FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { w in w.userID == userID }
            ))
            let existingWorkouts = userWorkouts.filter { $0.id != workout.id }
            let prs = PowerCurveService.detectPRs(newWorkout: workout, existingWorkouts: existingWorkouts)
            detectedPRs = prs
            if !prs.isEmpty {
                print("🎉 Detected \(prs.count) power curve PRs!")
                for pr in prs {
                    print("   - \(PowerCurveService.formatDuration(pr.duration)): \(Int(pr.watts))W")
                }
            }
        } catch {
            print("❌ Error saving workout: \(error)")
        }

        // Clear captured images
        capturedImagesForBenchmark = []

        state = .saved
        return workout
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

        // Save averages/summary row as interval with orderIndex = 0
        if let averages = table.averages {
            let averagesInterval = BenchmarkInterval(
                orderIndex: 0,
                time: averages.time?.text,
                meters: averages.meters.flatMap { Int($0.text) },
                splitPer500m: averages.splitPer500m?.text,
                strokeRate: averages.strokeRate.flatMap { Int($0.text) },
                heartRate: averages.heartRate.flatMap { Int($0.text) }
            )
            averagesInterval.workout = benchmarkWorkout
            context.insert(averagesInterval)
        }

        // Create BenchmarkIntervals from data rows (starting at orderIndex = 1)
        for (index, row) in table.rows.enumerated() {
            let benchmarkInterval = BenchmarkInterval(
                orderIndex: index + 1,  // Start at 1, since 0 is averages
                time: row.time?.text,
                meters: row.meters.flatMap { Int($0.text) },
                splitPer500m: row.splitPer500m?.text,
                strokeRate: row.strokeRate.flatMap { Int($0.text) },
                heartRate: row.heartRate.flatMap { Int($0.text) }
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
            isVariableInterval: new.isVariableInterval ?? existing.isVariableInterval,
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

    // MARK: - Multi-Screen Merge (deduplication for combining different screens)

    /// Merge rows from a second screen scan into the first screen's rows, deduplicating overlapping rows
    private func mergeScreenRows(firstScreen: [TableRow], secondScreen: [TableRow], category: WorkoutCategory?) -> [TableRow] {
        guard !firstScreen.isEmpty else { return secondScreen }
        guard !secondScreen.isEmpty else { return firstScreen }

        var result = firstScreen

        for newRow in secondScreen {
            let isDuplicate = result.contains { existingRow in
                rowsMatch(existingRow, newRow, category: category)
            }
            if !isDuplicate {
                result.append(newRow)
            }
        }

        print("📊 Multi-screen merge: \(firstScreen.count) + \(secondScreen.count) → \(result.count) rows")
        return result
    }

    private func rowsMatch(_ row1: TableRow, _ row2: TableRow, category: WorkoutCategory?) -> Bool {
        switch category {
        case .interval:
            // Intervals: match on meters AND time AND rate
            let metersMatch = row1.meters?.text == row2.meters?.text
            let timeMatch = row1.time?.text == row2.time?.text
            let rateMatch = row1.strokeRate?.text == row2.strokeRate?.text
            return metersMatch && timeMatch && rateMatch
        case .single:
            // Single: match on meters or time
            if let m1 = row1.meters?.text, let m2 = row2.meters?.text {
                return m1 == m2
            }
            if let t1 = row1.time?.text, let t2 = row2.time?.text {
                return t1 == t2
            }
            return false
        case .none:
            return false
        }
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
