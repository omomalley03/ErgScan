import SwiftUI
import SwiftData

/// Continuous OCR scanner with state-based UI (scanning → locked → saved)
struct ScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var assignmentService: AssignmentService
    @AppStorage("showDebugTabs") private var showDebugTabs = false

    let cameraService: CameraService
    @StateObject private var viewModel: ScannerViewModel

    // Optional parameters for coxswain scan-for-others workflow
    let scanOnBehalfOf: String?
    let scanOnBehalfOfUsername: String?
    let scanOnBehalfOfDisplayName: String?
    let assignmentID: String?
    let assignmentTeamID: String?

    @State private var showPRAlert = false
    @State private var navigateToPowerCurve = false

    init(
        cameraService: CameraService,
        scanOnBehalfOf: String? = nil,
        scanOnBehalfOfUsername: String? = nil,
        scanOnBehalfOfDisplayName: String? = nil,
        assignmentID: String? = nil,
        assignmentTeamID: String? = nil
    ) {
        self.cameraService = cameraService
        self.scanOnBehalfOf = scanOnBehalfOf
        self.scanOnBehalfOfUsername = scanOnBehalfOfUsername
        self.scanOnBehalfOfDisplayName = scanOnBehalfOfDisplayName
        self.assignmentID = assignmentID
        self.assignmentTeamID = assignmentTeamID
        _viewModel = StateObject(wrappedValue: ScannerViewModel(cameraService: cameraService))
    }

    var body: some View {
        Group {
            if case .manualInput(let partialTable) = viewModel.state {
                // Full-screen manual data entry
                ManualDataEntryView(
                    initialTable: partialTable,
                    validateOnLoad: viewModel.shouldValidateOnLoad,
                    scanOnBehalfOf: scanOnBehalfOf,
                    scanOnBehalfOfUsername: scanOnBehalfOfUsername,
                    assignmentID: assignmentID,
                    assignmentTeamID: assignmentTeamID,
                    onComplete: { table in
                        viewModel.state = .locked(table)
                    },
                    onCancel: {
                        viewModel.retake()
                    }
                )
            } else if case .locked(let table) = viewModel.state {
                // Full-screen data review (no camera)
                EditableWorkoutForm(
                    table: table,
                    scanOnBehalfOf: scanOnBehalfOf,
                    scanOnBehalfOfUsername: scanOnBehalfOfUsername,
                    assignmentID: assignmentID,
                    assignmentTeamID: assignmentTeamID,
                    onSave: { editedDate, selectedZone, isErgTest, privacy in
                        Task {
                            if let savedWorkout = await viewModel.saveWorkout(
                                context: modelContext,
                                customDate: editedDate,
                                intensityZone: selectedZone,
                                isErgTest: isErgTest,
                                privacy: privacy,
                                scanOnBehalfOfUserID: scanOnBehalfOf,
                                scanOnBehalfOfUsername: scanOnBehalfOfUsername
                            ) {
                                // Publish to social feed if user has username
                                var sharedWorkoutID: String? = nil
                                if let username = currentUser?.username, !username.isEmpty, privacy != WorkoutPrivacy.privateOnly.rawValue {
                                    sharedWorkoutID = await socialService.publishWorkout(
                                        workoutType: savedWorkout.workoutType,
                                        date: savedWorkout.date,
                                        totalTime: savedWorkout.totalTime,
                                        totalDistance: savedWorkout.totalDistance ?? 0,
                                        averageSplit: savedWorkout.averageSplit ?? "",
                                        intensityZone: savedWorkout.intensityZone ?? "",
                                        isErgTest: savedWorkout.isErgTest,
                                        localWorkoutID: savedWorkout.id.uuidString,
                                        privacy: privacy,
                                        onBehalfOfUserID: scanOnBehalfOf,
                                        onBehalfOfUsername: scanOnBehalfOfUsername,
                                        onBehalfOfDisplayName: scanOnBehalfOfDisplayName
                                    )

                                    // Mark workout as published
                                    if let recordID = sharedWorkoutID {
                                        savedWorkout.sharedWorkoutRecordID = recordID
                                        try? modelContext.save()
                                    }
                                }

                                // Submit to assignment if this is for an assignment
                                if let assignmentID = assignmentID, let teamID = assignmentTeamID {
                                    do {
                                        try await assignmentService.submitWorkout(
                                            assignmentID: assignmentID,
                                            teamID: teamID,
                                            workoutRecordID: savedWorkout.id.uuidString,
                                            sharedWorkoutRecordID: sharedWorkoutID,
                                            totalDistance: savedWorkout.totalDistance ?? 0,
                                            totalTime: savedWorkout.totalTime,
                                            averageSplit: savedWorkout.averageSplit ?? "",
                                            onBehalfOfUserID: scanOnBehalfOf,
                                            onBehalfOfUsername: scanOnBehalfOfUsername
                                        )
                                        print("✅ Workout submitted to assignment \(assignmentID)")
                                    } catch {
                                        print("❌ Failed to submit workout to assignment: \(error)")
                                    }
                                }
                            }
                        }
                    },
                    onRetake: {
                        viewModel.retake()
                    }
                )
            } else {
                mainScannerLayout
            }
        }
        .task {
            await viewModel.setupCamera()
        }
        .onAppear {
            viewModel.currentUser = currentUser
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    viewModel.stopCamera()
                    dismiss()
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.state) { oldState, newState in
            // Show PR alert when transitioning to saved state if PRs were detected
            if case .saved = newState, !viewModel.detectedPRs.isEmpty {
                showPRAlert = true
            }
        }
        .alert("Wattage PR!", isPresented: $showPRAlert) {
            Button("View Power Curve") {
                navigateToPowerCurve = true
            }
            Button("OK", role: .cancel) { }
        } message: {
            if viewModel.detectedPRs.count == 1 {
                Text("You set a new power PR at \(PowerCurveService.formatDuration(viewModel.detectedPRs[0].duration)): \(Int(viewModel.detectedPRs[0].watts))W!")
            } else {
                let durations = viewModel.detectedPRs.map { PowerCurveService.formatDuration($0.duration) }.joined(separator: ", ")
                Text("You set \(viewModel.detectedPRs.count) new power PRs at: \(durations)")
            }
        }
        .navigationDestination(isPresented: $navigateToPowerCurve) {
            PowerCurveView()
        }
    }

    // MARK: - Main Scanner Layout

    @ViewBuilder
    private var mainScannerLayout: some View {
        VStack(spacing: 0) {
            // ---- TOP HALF: Camera preview OR incomplete prompt table preview ----
            if case .incompletePrompt(let table, _) = viewModel.state {
                incompletePromptTablePreview(table: table)
                    .frame(maxHeight: .infinity)
            } else {
                ZStack {
                    if viewModel.cameraService.isSessionRunning {
                        CameraPreviewView(previewLayer: viewModel.cameraService.previewLayer)
                    } else {
                        Color.black
                    }

                    switch viewModel.state {
                    case .ready, .capturing:
                        PositioningGuideView(hint: "Get close so erg LCD fills the square")
                    case .locked:
                        LockedGuideOverlay()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()
            }

            // ---- BOTTOM HALF: State-based content ----
            VStack(spacing: 0) {
                switch viewModel.state {
                case .ready:
                    readyContent
                case .capturing:
                    capturingContent
                case .incompletePrompt(let table, let firstScan):
                    incompletePromptButtons(table: table, isFirstScan: firstScan)
                case .locked:
                    EmptyView() // Handled by full-screen EditableWorkoutForm above
                case .saved:
                    savedContent
                case .manualInput:
                    EmptyView() // Handled by full-screen ManualDataEntryView
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Ready State Content

    @ViewBuilder
    private var readyContent: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Align monitor in square guide")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.startScanning()
                }
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Start Scanning")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Capturing State Content

    @ViewBuilder
    private var capturingContent: some View {
        VStack(spacing: 0) {
            // Progress indicator
            VStack(spacing: 12) {
                HStack {
                    Text("Scanning...")// (Capture \(viewModel.captureCount))")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        ProgressView(value: viewModel.fieldProgress, total: 1.0)
                            .frame(width: 60)
                        Text("\(Int(viewModel.fieldProgress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .padding()

                // Progress message
                Text(progressMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            // Optional debug tabs (developer mode)
            if showDebugTabs, let parsedTable = viewModel.currentTable {
                Divider()
                DebugTabbedView(
                    debugResults: viewModel.debugResults,
                    parsedTable: parsedTable,
                    debugLog: viewModel.parserDebugLog
                )
                .frame(maxHeight: .infinity)
            }

            Spacer()
        }
    }

    private var progressMessage: String {
        if viewModel.fieldProgress < 0.3 {
            return "Looking for workout data..."
        } else if viewModel.fieldProgress < 0.7 {
            return "Filling in missing fields..."
        } else if viewModel.fieldProgress < 1.0 {
            return "Almost there! Completing final fields..."
        } else {
            return "All fields captured!"
        }
    }

    // MARK: - Saved State Content

    @ViewBuilder
    private var savedContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Workout Saved!")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Button {
                viewModel.retake()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Scan Another")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Incomplete Prompt Content

    @ViewBuilder
    private func incompletePromptTablePreview(table: RecognizedTable) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("More Data to Scan?")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text(getCompletenessMessage(table))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )

                Divider()

                Text("Current Data (\(table.rows.count) rows)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show preview of captured data
                if let avg = table.averages {
                    HStack {
                        Text("Avg").frame(width: 60, alignment: .leading)
                        Text(avg.time?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(avg.meters?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(avg.splitPer500m?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(avg.strokeRate?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                }

                // Show all rows, not just first 5
                ForEach(Array(table.rows.enumerated()), id: \.offset) { idx, row in
                    HStack {
                        Text("#\(idx+1)").frame(width: 60, alignment: .leading)
                        Text(row.time?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.meters?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.splitPer500m?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.strokeRate?.text ?? "-").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func incompletePromptButtons(table: RecognizedTable, isFirstScan: Bool) -> some View {
        VStack(spacing: 12) {
            Text(isFirstScan ? "Scroll down on the monitor to show remaining splits, then scan again." : "Still missing data. Continue scrolling and scanning, or save what you have.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top)

            Button {
                Task {
                    await viewModel.continueScanning()
                }
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Scan Next Screen")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button {
                viewModel.retryScan()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry Scan")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }

            Button {
                viewModel.acceptIncompleteData()
            } label: {
                HStack {
                    Image(systemName: "pencil.circle")
                    Text("Edit Manually")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func getCompletenessMessage(_ table: RecognizedTable) -> String {
        let check = table.checkDataCompleteness()
        if let reason = check.reason {
            return reason
        }
        return "Data may be incomplete. Scroll down on the monitor to see more splits."
    }

}

#Preview {
    ScannerView(cameraService: CameraService())
        .modelContainer(for: [Workout.self, Interval.self])
}
