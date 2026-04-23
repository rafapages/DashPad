import AVFoundation
import CoreImage
import UIKit
import Vision

struct CaptureResult {
    let luminance: Double           // average frame luminance, 0–255
    let observations: [VNDetectedObjectObservation]
    let debugImage: UIImage?        // last sampled frame for debug view
}

/// Starts a fresh AVCaptureSession on demand, waits a fixed warm-up period
/// for AE to settle, grabs one video frame, then tears the session down.
/// The camera LED is on for ~3 seconds per sample, not continuously.
class PresenceDetector: NSObject {
    var onCaptureResult: ((CaptureResult) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.rafapages.dashpad.camera", qos: .utility)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Seconds the session runs before we accept a frame. Gives AE time to
    // converge from a cold start — 3 s is comfortable for any lighting condition.
    private let warmupDuration: TimeInterval = 3

    // Main thread only — prevents overlapping captures.
    private var captureInProgress = false

    // sessionQueue only.
    private var pendingSession: AVCaptureSession?
    private var readyToCapture = false
    private var didCapture = false
    private var detectionMode: DetectionMode = .body
    private var darkLuminanceThreshold: Double = 20.0

    // MARK: - Public

    /// Must be called on the main thread.
    func captureOnce(detectionMode: DetectionMode, darkLuminanceThreshold: Double) {
        guard !captureInProgress else { return }
        captureInProgress = true

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.fail()
                return
            }
            self.sessionQueue.async {
                self.detectionMode = detectionMode
                self.darkLuminanceThreshold = darkLuminanceThreshold
                self.performCapture()
            }
        }
    }

    /// Resets capture state and reports a zero-luminance result so the
    /// KioskManager state machine can schedule the next attempt normally.
    private func fail() {
        DispatchQueue.main.async { [weak self] in
            self?.captureInProgress = false
            self?.onCaptureResult?(CaptureResult(luminance: 0, observations: [], debugImage: nil))
        }
    }

    // MARK: - Session setup

    private func performCapture() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            fail()
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(videoOutput) else {
            fail()
            return
        }

        session.addInput(input)
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            let angle = videoRotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        pendingSession = session
        readyToCapture = false
        didCapture = false

        session.startRunning()

        // Let AE settle, then accept the next arriving frame.
        sessionQueue.asyncAfter(deadline: .now() + warmupDuration) { [weak self] in
            self?.readyToCapture = true
        }
    }

    private func videoRotationAngle() -> CGFloat {
        var angle: CGFloat = 90
        DispatchQueue.main.sync {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
            else { return }
            switch scene.effectiveGeometry.interfaceOrientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeRight:     angle = 180
            case .landscapeLeft:      angle = 0
            default:                  angle = 90
            }
        }
        return angle
    }

    // MARK: - Detection

    private func detectPresence(
        in pixelBuffer: CVPixelBuffer,
        completion: @escaping ([VNDetectedObjectObservation]) -> Void
    ) {
        let handler: VNRequestCompletionHandler = { req, _ in
            completion(req.results as? [VNDetectedObjectObservation] ?? [])
        }
        let request: VNRequest = detectionMode == .face
            ? VNDetectFaceRectanglesRequest(completionHandler: handler)
            : VNDetectHumanRectanglesRequest(completionHandler: handler)

        // Buffer is pre-rotated and mirrored via the connection settings.
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer).perform([request])
    }

    // MARK: - Luminance

    private func averageLuminance(from pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var total: Double = 0
        var count = 0
        let step = 8
        for row in stride(from: 0, to: height, by: step) {
            for col in stride(from: 0, to: width, by: step) {
                let off = row * bytesPerRow + col * 4
                total += 0.114 * Double(ptr[off])       // B
                       + 0.587 * Double(ptr[off + 1])   // G
                       + 0.299 * Double(ptr[off + 2])   // R
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PresenceDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard readyToCapture, !didCapture,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        readyToCapture = false
        didCapture = true

        // Tear down the session — LED off after this returns.
        let session = pendingSession
        pendingSession = nil
        sessionQueue.async { session?.stopRunning() }

        let lum = averageLuminance(from: pixelBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let debugImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
            .map { UIImage(cgImage: $0) }

        guard lum >= darkLuminanceThreshold else {
            DispatchQueue.main.async { [weak self] in
                self?.captureInProgress = false
                self?.onCaptureResult?(CaptureResult(luminance: lum, observations: [], debugImage: debugImage))
            }
            return
        }

        // Vision is synchronous — runs on sessionQueue while pixelBuffer is valid.
        detectPresence(in: pixelBuffer) { [weak self] observations in
            DispatchQueue.main.async {
                self?.captureInProgress = false
                self?.onCaptureResult?(CaptureResult(luminance: lum, observations: observations, debugImage: debugImage))
            }
        }
    }
}
