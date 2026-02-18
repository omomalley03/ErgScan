import SwiftUI
import PhotosUI
import SwiftData

/// Upload a photo of a PM5 screen, pan/zoom to align within the positioning guide,
/// then run the same OCR + parsing pipeline as the live scanner.
struct ImageUploadScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var socialService: SocialService

    // MARK: - Photo Picker State

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    // MARK: - Interactive Image Viewer State

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - Processing State

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var resultTable: RecognizedTable?
    @State private var showManualInput = false
    @State private var showLockedResult = false
    @State private var shouldValidateOnLoad = false
    @State private var capturedImageData: Data?
    @State private var viewerSize: CGSize = .zero
    @State private var detectedPRs: [(duration: Double, watts: Double)] = []
    @State private var showPRAlert = false
    @State private var navigateToPowerCurve = false

    // Services (no camera needed)
    private let visionService = VisionService()
    private let tableParser = TableParserService()

    var body: some View {
        NavigationStack {
            Group {
                if showManualInput {
                    ManualDataEntryView(
                        initialTable: resultTable,
                        validateOnLoad: shouldValidateOnLoad,
                        onComplete: { table in
                            resultTable = table
                            showManualInput = false
                            showLockedResult = true
                        },
                        onCancel: {
                            showManualInput = false
                            resultTable = nil
                        }
                    )
                } else if showLockedResult, let table = resultTable {
                    EditableWorkoutForm(
                        table: table,
                        onSave: { editedDate, selectedZone, isErgTest, privacy in
                            Task {
                                await saveWorkout(
                                    table: table,
                                    customDate: editedDate,
                                    intensityZone: selectedZone,
                                    isErgTest: isErgTest,
                                    privacy: privacy
                                )
                            }
                        },
                        onRetake: {
                            showLockedResult = false
                            resultTable = nil
                        }
                    )
                } else if let image = selectedImage {
                    imageViewerWithGuide(image: image)
                } else {
                    photoPickerPrompt
                }
            }
            .navigationTitle(selectedImage != nil && !showLockedResult && !showManualInput ? "Align Photo" : "Upload Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if selectedImage != nil && !showLockedResult && !showManualInput {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Change") {
                            resetImageState()
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Wattage PR!", isPresented: $showPRAlert) {
                Button("View Power Curve") {
                    navigateToPowerCurve = true
                }
                Button("OK", role: .cancel) { }
            } message: {
                if detectedPRs.count == 1 {
                    Text("You set a new power PR at \(PowerCurveService.formatDuration(detectedPRs[0].duration)): \(Int(detectedPRs[0].watts))W!")
                } else {
                    let durations = detectedPRs.map { PowerCurveService.formatDuration($0.duration) }.joined(separator: ", ")
                    Text("You set \(detectedPRs.count) new power PRs at: \(durations)")
                }
            }
            .navigationDestination(isPresented: $navigateToPowerCurve) {
                PowerCurveView()
            }
        }
    }

    // MARK: - Photo Picker Prompt

    @ViewBuilder
    private var photoPickerPrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Select a photo of your erg monitor")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.fill")
                    Text("Choose Photo")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                guard let newItem = newItem else { return }

                do {
                    isProcessing = true
                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                        errorMessage = "Could not load image data. Please try selecting a different photo."
                        isProcessing = false
                        return
                    }

                    guard let image = UIImage(data: data) else {
                        errorMessage = "Could not create image from data. Please try a different photo."
                        isProcessing = false
                        return
                    }

                    selectedImage = image
                    capturedImageData = image.jpegData(compressionQuality: 0.8)
                    isProcessing = false
                } catch {
                    isProcessing = false

                    // Check if it's an iCloud download issue
                    let nsError = error as NSError
                    if nsError.domain == "PHAssetExportRequestErrorDomain" ||
                       nsError.domain == "CloudPhotoLibraryErrorDomain" {
                        errorMessage = "This photo is stored in iCloud and couldn't be downloaded. Please ensure you have an internet connection and try again, or select a photo that's already on your device."
                    } else {
                        errorMessage = "Failed to load photo: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Interactive Image Viewer with Guide Overlay

    @ViewBuilder
    private func imageViewerWithGuide(image: UIImage) -> some View {
        VStack(spacing: 0) {
            // Image viewer with guide overlay
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    // Interactive image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(currentScale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(magnificationGesture, dragGesture(viewSize: geometry.size, imageSize: image.size))
                        )

                    // Guide overlay (not interactive)
                    PositioningGuideView()
                }
                .clipped()
                .onAppear { viewerSize = geometry.size }
                .onChange(of: geometry.size) { _, newSize in viewerSize = newSize }
            }
            .frame(maxHeight: .infinity)

            // Scan button
            VStack(spacing: 12) {
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Processing image...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Button {
                        Task {
                            await scanImage(image)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder")
                            Text("Scan")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                currentScale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { value in
                let newScale = lastScale * value
                currentScale = min(max(newScale, 1.0), 5.0)
                lastScale = currentScale

                // If zoomed out to 1x, reset offset
                if currentScale <= 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private func dragGesture(viewSize: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                // Clamp so image can't be dragged entirely out of the guide
                offset = clampedOffset(offset, viewSize: viewSize, imageSize: imageSize)
                lastOffset = offset
            }
    }

    /// Clamp offset so the scaled image always covers the guide area
    private func clampedOffset(_ proposed: CGSize, viewSize: CGSize, imageSize: CGSize) -> CGSize {
        // Calculate the image's displayed size (scaledToFit inside viewSize, then scaled)
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let fittedSize: CGSize
        if imageAspect > viewAspect {
            // Image is wider than view
            fittedSize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
        } else {
            // Image is taller than view
            fittedSize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
        }

        let scaledWidth = fittedSize.width * currentScale
        let scaledHeight = fittedSize.height * currentScale

        // The guide is a square with side = viewSize.width, centered vertically
        let guideSide = viewSize.width
        let guideMinX: CGFloat = 0
        let guideMaxX = guideSide
        let guideMinY = (viewSize.height - guideSide) / 2
        let guideMaxY = guideMinY + guideSide

        // Image center when at offset (0,0) is viewSize center
        let imageCenterX = viewSize.width / 2 + proposed.width
        let imageCenterY = viewSize.height / 2 + proposed.height

        let imageMinX = imageCenterX - scaledWidth / 2
        let imageMaxX = imageCenterX + scaledWidth / 2
        let imageMinY = imageCenterY - scaledHeight / 2
        let imageMaxY = imageCenterY + scaledHeight / 2

        var dx: CGFloat = 0
        var dy: CGFloat = 0

        // Horizontal clamping
        if scaledWidth >= guideSide {
            if imageMinX > guideMinX { dx = guideMinX - imageMinX }
            if imageMaxX < guideMaxX { dx = guideMaxX - imageMaxX }
        } else {
            // Image smaller than guide horizontally — center it
            dx = (viewSize.width / 2) - imageCenterX
        }

        // Vertical clamping
        if scaledHeight >= guideSide {
            if imageMinY > guideMinY { dy = guideMinY - imageMinY }
            if imageMaxY < guideMaxY { dy = guideMaxY - imageMaxY }
        } else {
            // Image smaller than guide vertically — center it
            dy = (viewSize.height / 2) - imageCenterY
        }

        return CGSize(width: proposed.width + dx, height: proposed.height + dy)
    }

    // MARK: - OCR Processing

    private func scanImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil

        do {
            // Crop image to the guide region
            guard let croppedImage = cropImageToGuide(image) else {
                errorMessage = "Failed to crop image. Try adjusting the alignment."
                isProcessing = false
                return
            }

            // Run OCR using accurate mode (same as live scanner still captures)
            let ocrResults = try await visionService.recognizeText(in: croppedImage)

            guard !ocrResults.isEmpty else {
                errorMessage = "No text detected. Make sure the erg monitor screen is visible."
                isProcessing = false
                return
            }

            // Convert to guide-relative coordinates (same axis flip as ScannerViewModel)
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

            // Parse through the same 9-phase TableParserService pipeline
            let parseResult = tableParser.parseTable(from: guideRelativeResults)
            var table = parseResult.table

            // Default date to today (same as live scanner)
            if table.date == nil {
                table = RecognizedTable(
                    workoutType: table.workoutType,
                    category: table.category,
                    date: Date(),
                    totalTime: table.totalTime,
                    description: table.description,
                    reps: table.reps,
                    workPerRep: table.workPerRep,
                    restPerRep: table.restPerRep,
                    isVariableInterval: table.isVariableInterval,
                    totalDistance: table.totalDistance,
                    averages: table.averages,
                    rows: table.rows,
                    averageConfidence: table.averageConfidence
                )
            }

            resultTable = table

            // Route based on completeness and validation (same as live scanner)
            if isTableReadyToLock(table) {
                let completenessCheck = table.checkDataCompleteness()

                if completenessCheck.isComplete {
                    // Run validation checks (split accuracy + consistency)
                    if validateScanData(table) {
                        // All checks pass — lock normally
                        showLockedResult = true
                        print("✅ Upload locked with complete data! (\(table.rows.count) rows)")
                    } else {
                        // Validation failed — send to manual input for correction
                        print("⚠️ Upload data has validation errors, redirecting to manual input")
                        shouldValidateOnLoad = true
                        showManualInput = true
                    }
                } else {
                    // Data meets locking criteria but is incomplete
                    print("⚠️ Upload meets locking criteria but data appears incomplete")
                    if let reason = completenessCheck.reason {
                        print("   Reason: \(reason)")
                    }
                    shouldValidateOnLoad = true
                    showManualInput = true
                }
            } else {
                // Missing essential fields — send to manual input
                shouldValidateOnLoad = true
                showManualInput = true
            }

            isProcessing = false

        } catch {
            errorMessage = "OCR processing failed: \(error.localizedDescription)"
            isProcessing = false
        }
    }

    /// Crop the displayed image to match the square guide region, accounting for zoom and pan.
    private func cropImageToGuide(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Use the stored viewer size captured from GeometryReader
        let viewSize = viewerSize
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        // Calculate fitted image size (same as .scaledToFit)
        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let fittedSize: CGSize
        if imageAspect > viewAspect {
            fittedSize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
        } else {
            fittedSize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
        }

        // The guide is a square with side = viewSize.width, centered in the view
        let guideSide = viewSize.width
        let guideOriginInView = CGPoint(
            x: 0,
            y: (viewSize.height - guideSide) / 2
        )

        // The image center in view coordinates (accounting for offset)
        let imageCenterInView = CGPoint(
            x: viewSize.width / 2 + offset.width,
            y: viewSize.height / 2 + offset.height
        )

        // The image bounds in view coordinates after scaling
        let scaledFittedSize = CGSize(
            width: fittedSize.width * currentScale,
            height: fittedSize.height * currentScale
        )
        let imageOriginInView = CGPoint(
            x: imageCenterInView.x - scaledFittedSize.width / 2,
            y: imageCenterInView.y - scaledFittedSize.height / 2
        )

        // Guide rect relative to the scaled image (in view points)
        let guideInImage = CGRect(
            x: (guideOriginInView.x - imageOriginInView.x),
            y: (guideOriginInView.y - imageOriginInView.y),
            width: guideSide,
            height: guideSide
        )

        // Convert from view-space (within the scaled image) to pixel-space
        let scaleX = imageSize.width / scaledFittedSize.width
        let scaleY = imageSize.height / scaledFittedSize.height

        let cropRect = CGRect(
            x: max(0, guideInImage.origin.x * scaleX),
            y: max(0, guideInImage.origin.y * scaleY),
            width: min(imageSize.width, guideInImage.width * scaleX),
            height: min(imageSize.height, guideInImage.height * scaleY)
        )

        // Ensure crop rect is within image bounds
        let clampedRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clampedRect.isEmpty, clampedRect.width > 10, clampedRect.height > 10 else {
            return nil
        }

        guard let croppedCG = cgImage.cropping(to: clampedRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Save Workout

    private func saveWorkout(table: RecognizedTable, customDate: Date?, intensityZone: IntensityZone?, isErgTest: Bool, privacy: String) async {
        guard let currentUser = currentUser else {
            errorMessage = "Must be signed in to save workouts"
            return
        }

        let workoutDate = customDate ?? table.date ?? Date()

        let workout = Workout(
            date: workoutDate,
            workoutType: table.workoutType ?? "Unknown",
            category: table.category ?? .single,
            totalTime: table.totalTime ?? "",
            totalDistance: table.totalDistance,
            ocrConfidence: table.averageConfidence,
            imageData: capturedImageData,
            intensityZone: intensityZone?.rawValue,
            isErgTest: isErgTest
        )

        workout.user = currentUser
        workout.userID = currentUser.appleUserID
        workout.syncedToCloud = true
        workout.sharePrivacy = privacy

        modelContext.insert(workout)

        // Save averages as interval with orderIndex = 0
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
            modelContext.insert(averagesInterval)
        }

        // Create intervals from data rows
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
            modelContext.insert(interval)
        }

        do {
            try modelContext.save()

            // Detect PRs on the power curve
            do {
                let userID = currentUser.appleUserID
                let userWorkouts = try modelContext.fetch(FetchDescriptor<Workout>(
                    predicate: #Predicate<Workout> { w in w.userID == userID }
                ))
                let existingWorkouts = userWorkouts.filter { $0.id != workout.id }
                let prs = PowerCurveService.detectPRs(newWorkout: workout, existingWorkouts: existingWorkouts)
                detectedPRs = prs
                print("🔥 Detected \(prs.count) PRs from upload")
            } catch {
                print("⚠️ Failed to detect PRs: \(error)")
            }

            // Publish to social feed
            if let username = currentUser.username, !username.isEmpty, privacy != WorkoutPrivacy.privateOnly.rawValue {
                let recordID = await socialService.publishWorkout(
                    workoutType: workout.workoutType,
                    date: workout.date,
                    totalTime: workout.totalTime,
                    totalDistance: workout.totalDistance ?? 0,
                    averageSplit: workout.averageSplit ?? "",
                    intensityZone: workout.intensityZone ?? "",
                    isErgTest: workout.isErgTest,
                    localWorkoutID: workout.id.uuidString,
                    privacy: privacy
                )

                // Mark workout as published
                if let recordID = recordID {
                    workout.sharedWorkoutRecordID = recordID
                    try? modelContext.save()
                }
            }

            // Show PR alert after dismissing if PRs were detected
            dismiss()
            if !detectedPRs.isEmpty {
                // Small delay to allow dismiss animation to complete
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                showPRAlert = true
            }
        } catch {
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }
    }

    // MARK: - Validation

    /// Check if table is ready to lock (all splits have essential data)
    private func isTableReadyToLock(_ table: RecognizedTable) -> Bool {
        // Must have workout type
        guard table.workoutType != nil else {
            print("⏳ Upload not ready: Missing workout type")
            return false
        }

        // Must have averages with all 4 essential fields: time, meters, split, rate
        guard let averages = table.averages,
              averages.time != nil,
              averages.meters != nil,
              averages.splitPer500m != nil,
              averages.strokeRate != nil else {
            print("⏳ Upload not ready: Missing averages (need all 4 fields: time, meters, split, rate)")
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
                print("⏳ Upload not ready: Only \(completeCount)/\(table.rows.count) rows have time/meters/split")
                return false
            }

            // All rows except the last must have stroke rate
            if table.rows.count > 1 {
                let allButLastHaveRate = table.rows.dropLast().allSatisfy { row in
                    row.strokeRate != nil
                }

                guard allButLastHaveRate else {
                    let rateCount = table.rows.filter { $0.strokeRate != nil }.count
                    print("⏳ Upload not ready: Only \(rateCount)/\(table.rows.count) rows have stroke rate")
                    return false
                }
            }

            // Last row: stroke rate required if distance >= 100m
            if let lastRow = table.rows.last, lastRow.strokeRate == nil {
                let lastRowMeters = Int(lastRow.meters?.text.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
                if lastRowMeters >= 100 {
                    print("⏳ Upload not ready: Last row has \(lastRowMeters)m but no stroke rate (required for >= 100m)")
                    return false
                }
            }
        }

        print("✅ Upload ready to lock: All essential data present")
        return true
    }

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
                print("⚠️ Upload split accuracy error at row \(i): expected \(floored), actual \(actualSplit)")
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
                        print("⚠️ Upload split consistency error at row \(i): gap \(current - prev) ≠ expected \(firstMeters)")
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
                        print("⚠️ Upload split consistency error at row \(i): time gap \(current - prev) ≠ expected \(firstTime)")
                        return false
                    }
                }
            }
        }

        // 3. Meters completeness (already checked by checkDataCompleteness — skip)
        return true
    }

    // MARK: - Helpers

    private func resetImageState() {
        selectedItem = nil
        selectedImage = nil
        currentScale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
        resultTable = nil
        showLockedResult = false
        showManualInput = false
        capturedImageData = nil
    }
}
