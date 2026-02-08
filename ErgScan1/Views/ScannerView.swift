import SwiftUI
import SwiftData

/// Debug scanner: top half camera + guide, bottom half OCR results with guide-relative coords
struct ScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // ---- TOP HALF: Camera preview or captured photo ----
            ZStack {
                if let capturedImage = viewModel.capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else if viewModel.cameraService.isSessionRunning {
                    CameraPreviewView(previewLayer: viewModel.cameraService.previewLayer)
                } else {
                    Color.black
                }

                // Square positioning guide (only during live preview)
                if viewModel.capturedImage == nil {
                    PositioningGuideView()
                }

                // Processing indicator
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()

            // ---- BOTTOM HALF: Debug tabbed view ----
            VStack(spacing: 0) {
                if viewModel.capturedImage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Align monitor in square, then capture")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DebugTabbedView(
                        debugResults: viewModel.debugResults,
                        parsedTable: viewModel.parsedTable,
                        debugLog: viewModel.parserDebugLog
                    )
                }

                // Bottom controls
                HStack(spacing: 32) {
                    if viewModel.capturedImage != nil {
                        Button {
                            viewModel.retake()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 28))
                                Text("Retake")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.accentColor)
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.capturePhoto()
                            }
                        } label: {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.accentColor)
                        }
                        .disabled(viewModel.isProcessing)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
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
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Workout.self, Interval.self])
}
