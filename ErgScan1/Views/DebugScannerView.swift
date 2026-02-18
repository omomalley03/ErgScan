import SwiftUI
import PhotosUI
import UIKit

/// Simplified debug scanner: pick Scan (single capture) or Upload, then inspect
/// raw OCR results + parser debug log in DebugTabbedView.
/// OCR, scanning, and parsing logic is identical to the production flows — no changes there.
struct DebugScannerView: View {

    // MARK: - Mode

    private enum DebugMode { case scan, upload }
    @State private var mode: DebugMode? = nil

    // MARK: - Camera (scan mode)

    @StateObject private var cameraService = CameraService()
    @State private var cameraReady = false

    // MARK: - Services (same instances as production)

    private let visionService = VisionService()
    private let tableParser = TableParserService()

    // MARK: - Processing

    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    // MARK: - Results

    @State private var debugResults: [GuideRelativeOCRResult] = []
    @State private var parsedTable: RecognizedTable? = nil
    @State private var debugLog: String = ""
    @State private var showResults = false

    // MARK: - Upload

    @State private var selectedItem: PhotosPickerItem? = nil

    // MARK: - Body

    var body: some View {
        Group {
            switch mode {
            case .none:
                modeSelectionView
            case .scan:
                scanView
            case .upload:
                uploadView
            }
        }
        .navigationTitle("Debug Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        stopCamera()
                        mode = nil
                        showResults = false
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $showResults) {
            NavigationStack {
                DebugTabbedView(
                    debugResults: debugResults,
                    parsedTable: parsedTable,
                    debugLog: debugLog
                )
                .navigationTitle("Debug Results")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            showResults = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mode Selection

    private var modeSelectionView: some View {
        VStack(spacing: 40) {
            Spacer()

            Image(systemName: "ladybug.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Choose a debug mode")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 32) {
                // Scan button
                VStack(spacing: 12) {
                    Button {
                        mode = .scan
                        Task { await setupCamera() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 88, height: 88)
                                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        }
                    }
                    Text("Scan")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Upload button
                VStack(spacing: 12) {
                    Button {
                        mode = .upload
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 88, height: 88)
                                .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                            Image(systemName: "photo.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        }
                    }
                    Text("Upload")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            Spacer()
        }
    }

    // MARK: - Scan View

    private var scanView: some View {
        VStack(spacing: 0) {
            // Camera preview with guide overlay
            ZStack {
                Color.black

                if cameraReady {
                    CameraPreviewView(previewLayer: cameraService.previewLayer)
                } else {
                    ProgressView("Starting camera...")
                        .foregroundColor(.white)
                }

                PositioningGuideView()
            }
            .frame(maxHeight: .infinity)

            // Capture button
            VStack(spacing: 12) {
                if isProcessing {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Processing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Button {
                        Task { await debugCapture() }
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text("Capture")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(cameraReady ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!cameraReady)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
        }
        .onDisappear { stopCamera() }
    }

    // MARK: - Upload View

    private var uploadView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Select a photo of your erg monitor")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isProcessing {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Processing image...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
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
            }

            Spacer()
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndProcess(newItem) }
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() async {
        let authorized = await cameraService.requestCameraPermission()
        guard authorized else {
            errorMessage = "Camera permission denied. Please enable in Settings."
            return
        }
        do {
            try await cameraService.setupCamera()
            cameraService.startSession()
            // Brief delay so session is confirmed running
            try? await Task.sleep(nanoseconds: 400_000_000)
            cameraReady = cameraService.isSessionRunning
            if !cameraReady {
                errorMessage = "Camera failed to start. Please try again."
            }
        } catch {
            errorMessage = "Camera error: \(error.localizedDescription)"
        }
    }

    private func stopCamera() {
        cameraService.stopSession()
        cameraReady = false
    }

    // MARK: - Scan: single capture (same logic as ScannerViewModel.captureAndProcess, no loop/merge)

    private func debugCapture() async {
        isProcessing = true
        defer { isProcessing = false }

        guard let fullImage = await cameraService.capturePhoto(),
              let fullCG = fullImage.cgImage else {
            errorMessage = "Failed to capture photo."
            return
        }

        // Crop to center square (same as ScannerViewModel)
        let side = min(fullCG.width, fullCG.height)
        let cropRect = CGRect(
            x: (fullCG.width - side) / 2,
            y: (fullCG.height - side) / 2,
            width: side,
            height: side
        )
        guard let croppedCG = fullCG.cropping(to: cropRect) else {
            errorMessage = "Failed to crop photo."
            return
        }
        let croppedImage = UIImage(cgImage: croppedCG, scale: fullImage.scale, orientation: fullImage.imageOrientation)

        do {
            // OCR — same call as ScannerViewModel
            let ocrResults = try await visionService.recognizeText(in: croppedImage)

            // Convert to guide-relative coordinates (y-flip only; Vision handles orientation).
            let guideRelative = ocrResults.map { r -> GuideRelativeOCRResult in
                let b = r.boundingBox
                return GuideRelativeOCRResult(
                    original: r,
                    guideRelativeBox: CGRect(x: b.origin.x, y: 1 - b.origin.y - b.height, width: b.width, height: b.height)
                )
            }

            // Parse — same as ScannerViewModel
            let parseResult = tableParser.parseTable(from: guideRelative)

            debugResults = guideRelative
            parsedTable  = parseResult.table
            debugLog     = parseResult.debugLog
            showResults  = true
        } catch {
            errorMessage = "OCR error: \(error.localizedDescription)"
        }
    }

    // MARK: - Upload: load image then process as-is (no guide crop)

    private func loadAndProcess(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load image."
                return
            }

            // OCR — same call as ImageUploadScannerView
            let ocrResults = try await visionService.recognizeText(in: image)

            // Convert to guide-relative coordinates (y-flip only; Vision handles orientation).
            let guideRelative = ocrResults.map { r -> GuideRelativeOCRResult in
                let b = r.boundingBox
                return GuideRelativeOCRResult(
                    original: r,
                    guideRelativeBox: CGRect(x: b.origin.x, y: 1 - b.origin.y - b.height, width: b.width, height: b.height)
                )
            }

            // Parse — same as ImageUploadScannerView
            let parseResult = tableParser.parseTable(from: guideRelative)

            debugResults = guideRelative
            parsedTable  = parseResult.table
            debugLog     = parseResult.debugLog
            showResults  = true
        } catch {
            errorMessage = "Failed to process image: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DebugScannerView()
    }
}
