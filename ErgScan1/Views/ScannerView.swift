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

            // ---- BOTTOM HALF: Debug OCR results ----
            VStack(spacing: 0) {
                if viewModel.debugResults.isEmpty && viewModel.capturedImage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Align monitor in square, then capture")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.debugResults.isEmpty && viewModel.capturedImage != nil {
                    Text("No text detected inside guide")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Header — X = left-to-right, Y = top-to-bottom (guide-relative, top-left origin)
                    HStack {
                        Text("Text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Conf")
                            .frame(width: 45, alignment: .trailing)
                        Text("X")
                            .frame(width: 45, alignment: .trailing)
                        Text("Y")
                            .frame(width: 45, alignment: .trailing)
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))

                    // Results list sorted by Y (top-to-bottom)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(
                                Array(viewModel.debugResults
                                    .sorted { $0.guideRelativeBox.midY < $1.guideRelativeBox.midY }
                                    .enumerated()),
                                id: \.offset
                            ) { _, result in
                                HStack {
                                    Text(result.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.0f%%", result.confidence * 100))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(confidenceColor(result.confidence))
                                        .frame(width: 45, alignment: .trailing)
                                    Text(String(format: "%.2f", result.guideRelativeBox.midX))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .trailing)
                                    Text(String(format: "%.2f", result.guideRelativeBox.midY))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .trailing)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)

                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // Result count
                    Text("\(viewModel.debugResults.count) results inside guide")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
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

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 { return .green }
        if confidence > 0.5 { return .orange }
        return .red
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Workout.self, Interval.self])
}
