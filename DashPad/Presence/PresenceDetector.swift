import AVFoundation
import Vision

/// Captures frames from the front camera at a configurable interval and runs
/// VNDetectFaceRectanglesRequest on each frame. All processing is on-device;
/// no frames are stored or transmitted.
class PresenceDetector: NSObject {
    /// Called on the main thread when face presence changes.
    var onFaceDetected: ((Bool) -> Void)?
    var onFrameResult: (([VNFaceObservation]) -> Void)?

    var captureSession: AVCaptureSession?
    private var sampleInterval: Double = 2.0
    private var lastSampleTime: Date = .distantPast
    private let sessionQueue = DispatchQueue(label: "com.rafapages.dashpad.camera", qos: .utility)

    // MARK: - Control

    func start(sampleInterval: Double) {
        self.sampleInterval = sampleInterval
        guard captureSession == nil else { return }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.setupSession() }
        }
    }

    func stop() {
        let session = captureSession
        captureSession = nil
        sessionQueue.async { session?.stopRunning() }
        // Report no presence when camera stops
        DispatchQueue.main.async { self.onFaceDetected?(false) }
    }

    // MARK: - Session setup

    private func setupSession() {
        guard captureSession == nil else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }

        session.addInput(input)
        session.addOutput(output)

        captureSession = session
        sessionQueue.async { session.startRunning() }
    }

    // MARK: - Face detection

    private func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            let observations = req.results as? [VNFaceObservation] ?? []
            let detected = !observations.isEmpty
            DispatchQueue.main.async {
                self?.onFaceDetected?(detected)
                self?.onFrameResult?(observations)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PresenceDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastSampleTime) >= sampleInterval else { return }
        lastSampleTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detectFaces(in: pixelBuffer)
    }
}
