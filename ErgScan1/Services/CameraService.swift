import Foundation
import Combine
import AVFoundation
import UIKit

typealias FrameHandler = (CVPixelBuffer) -> Void

/// Camera service for preview, photo capture, and continuous video frame processing
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var isSessionRunning = false

    // MARK: - Private Properties

    private let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    // Video output for continuous frame capture
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoDataQueue = DispatchQueue(label: "com.ergscan.videodata", qos: .userInitiated)
    private var frameHandler: FrameHandler?

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

    // MARK: - Camera Setup

    func setupCamera() async throws {
        guard isAuthorized else {
            throw CameraError.notAuthorized
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo  // Full-resolution photo preset

        // Get back camera
        guard let camera = AVCaptureDevice.default(
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

        // Create photo output
        let output = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(output)
        photoOutput = output

        captureSession.commitConfiguration()
    }

    // MARK: - Session Control

    func startSession() {
        guard !isSessionRunning else { return }

        Task {
            captureSession.startRunning()
            isSessionRunning = captureSession.isRunning
        }
    }

    func stopSession() {
        guard isSessionRunning else { return }

        Task {
            captureSession.stopRunning()
            isSessionRunning = false
        }
    }

    // MARK: - Continuous Frame Capture

    /// Setup continuous video frame capture for real-time OCR
    func setupContinuousCapture(frameHandler: @escaping FrameHandler) async throws {
        self.frameHandler = frameHandler

        captureSession.beginConfiguration()

        // Create video data output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoDataQueue)

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
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
    }

    /// Stop continuous frame capture
    func stopContinuousCapture() {
        if let videoOutput = videoOutput {
            captureSession.removeOutput(videoOutput)
            self.videoOutput = nil
        }
        frameHandler = nil
    }

    // MARK: - Photo Capture

    func capturePhoto() async -> UIImage? {
        guard let photoOutput = photoOutput else { return nil }

        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let continuation = photoContinuation else { return }
            photoContinuation = nil

            if let error = error {
                print("Photo capture error: \(error.localizedDescription)")
                continuation.resume(returning: nil)
                return
            }

            guard let imageData = photo.fileDataRepresentation(),
                  let image = UIImage(data: imageData) else {
                continuation.resume(returning: nil)
                return
            }

            continuation.resume(returning: image)
        }
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

        Task { @MainActor in
            frameHandler?(pixelBuffer)
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
