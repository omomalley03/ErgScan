import SwiftUI
import SwiftData

/// Continuous OCR scanner with state-based UI (scanning → locked → saved)
struct ScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ScannerViewModel()
    @AppStorage("showDebugTabs") private var showDebugTabs = true  // Temporarily enabled for debugging
    @State private var showDebugLogs = false

    var body: some View {
        VStack(spacing: 0) {
            // ---- TOP HALF: Camera preview with state-based overlays ----
            ZStack {
                if viewModel.cameraService.isSessionRunning {
                    CameraPreviewView(previewLayer: viewModel.cameraService.previewLayer)
                } else {
                    Color.black
                }

                // State-based overlays
                switch viewModel.state {
                case .ready, .capturing:
                    // Square positioning guide during ready and capturing
                    PositioningGuideView()

                case .locked:
                    // Green checkmark overlay when locked
                    LockedGuideOverlay()

                case .saved:
                    // No overlay for saved state
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()

            // ---- BOTTOM HALF: State-based content ----
            VStack(spacing: 0) {
                switch viewModel.state {
                case .ready:
                    readyContent

                case .capturing:
                    capturingContent

                case .locked(let table):
                    VStack(spacing: 0) {
                        // Debug logs button
                        if !viewModel.allCapturesLog.isEmpty {
                            Button {
                                showDebugLogs = true
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("View Parser Logs (3 Captures)")
                                }
                                .font(.subheadline)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }

                        EditableWorkoutForm(
                            table: table,
                            onSave: {
                                Task {
                                    await viewModel.saveWorkout(context: modelContext)
                                }
                            },
                            onRetake: {
                                viewModel.retake()
                            }
                        )
                    }

                case .saved:
                    savedContent
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
        .task {
            await viewModel.setupCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogsView(logs: viewModel.allCapturesLog)
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
                    Text("Scanning... (Capture \(viewModel.captureCount))")
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
}

// MARK: - Debug Logs View

struct DebugLogsView: View {
    let logs: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)  // Enable text selection for copying
            }
            .navigationTitle("Parser Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logs
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Workout.self, Interval.self])
}
