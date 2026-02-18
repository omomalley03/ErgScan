import Foundation
import Combine
import AVFoundation
import UIKit
import CoreImage

typealias FrameHandler = (CVPixelBuffer) -> Void

/// Camera service for preview, photo capture, and continuous video frame processing
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var isSessionRunning = false
    @Published private(set) var isConfigured = false

    // MARK: - Private Properties

    private let captureSession = AVCaptureSession()

    // Video output for frame buffering
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoDataQueue = DispatchQueue(label: "com.ergscan.videodata", qos: .userInitiated)
    private var frameHandler: FrameHandler?
    nonisolated(unsafe) private var latestFrameBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    // MARK: - Authorization

    func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted

        case .denied, .restricted:
            isAuthorized = false
            return false

        @unknown default:
            isAuthorized = false
            return false
        }
    }

    /// Check if camera permission is already granted (no prompt)
    var isAlreadyAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    // MARK: - Camera Setup

    func setupCamera() async throws {
        guard isAuthorized else {
            throw CameraError.notAuthorized
        }

        // Skip if already configured (pre-warmed)
        guard !isConfigured else { return }

        captureSession.beginConfiguration()

        // Remove existing inputs to avoid duplicate input error
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        captureSession.sessionPreset = .photo  // Full-resolution photo preset

        // Prefer ultra-wide camera (supports macro/close-up), fall back to wide-angle
        guard let camera = AVCaptureDevice.default(
            .builtInUltraWideCamera,
            for: .video,
            position: .back
        ) ?? AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noCameraAvailable
        }

        // Create input
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        captureSession.addInput(input)

        // Configure autofocus and exposure
        try camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isFocusPointOfInterestSupported {
            camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        camera.unlockForConfiguration()

        // Remove existing outputs
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        // Create video data output for frame buffering
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoDataQueue)

        guard captureSession.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(output)
        videoOutput = output

        // Configure connection for portrait orientation
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Session Control

    func startSession() {
        let session = captureSession
        Task.detached {
            session.startRunning()
            await MainActor.run { [weak self] in
                self?.isSessionRunning = session.isRunning
            }
        }
    }

    func stopSession() {
        isSessionRunning = false
        let session = captureSession
        Task.detached {
            session.stopRunning()
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async -> UIImage? {
        // Small delay to ensure we have a fresh frame
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Get buffered frame (thread-safe)
        bufferLock.lock()
        let pixelBuffer = latestFrameBuffer
        bufferLock.unlock()

        guard let pixelBuffer = pixelBuffer else {
            print("⚠️ No frame buffered yet")
            return nil
        }

        // Convert CVPixelBuffer to UIImage
        return convertPixelBufferToUIImage(pixelBuffer)
    }

    private func convertPixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("⚠️ Failed to convert CVPixelBuffer to CGImage")
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Store latest frame in thread-safe buffer
        bufferLock.lock()
        latestFrameBuffer = pixelBuffer
        bufferLock.unlock()

        // Also forward to frameHandler if set (for future continuous OCR feature)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.frameHandler?(pixelBuffer)
        }
    }
}

// MARK: - Errors

enum CameraError: Error, LocalizedError {
    case notAuthorized
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access is not authorized. Please enable in Settings."
        case .noCameraAvailable:
            return "No camera available on this device."
        case .cannotAddInput:
            return "Cannot add camera input to capture session."
        case .cannotAddOutput:
            return "Cannot add video output to capture session."
        }
    }
}
