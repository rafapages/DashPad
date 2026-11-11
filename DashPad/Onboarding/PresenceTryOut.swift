// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// PresenceTryOut.swift - the setup flow's live presence demo: the front camera shown on screen,
// checked a few times a second, so stepping away and coming back visibly flips the display.
//
// This is deliberately separate from `PresenceDetector`. That one opens the camera for three
// seconds, takes a single frame and closes it again; a demo needs a continuous picture and an
// answer within a second. It is also the only place the app ever shows the camera image.

import AVFoundation
import Combine
import SwiftUI
import Vision

// MARK: - Model

final class PresenceTryOutModel: ObservableObject {
    enum CameraState { case starting, running, unavailable }

    @Published private(set) var cameraState: CameraState = .starting
    @Published private(set) var personPresent = false
    /// The two things the step asks the user to try, ticked off as they happen.
    @Published private(set) var hasSteppedAway = false
    @Published private(set) var hasComeBack = false
    @Published private(set) var isRoomDark = false

    let camera = TryOutCamera()

    /// Consecutive empty frames before the person counts as gone. One missed detection is
    /// common when someone turns or leans, and should not flicker the display.
    private let missesBeforeAway = 3
    private var misses = 0
    private var darkLuminanceThreshold: Double = 20

    func start(detectionMode: DetectionMode, darkLuminanceThreshold: Double) {
        self.darkLuminanceThreshold = darkLuminanceThreshold
        cameraState = .starting
        camera.onSample = { [weak self] detected, luminance in
            DispatchQueue.main.async { self?.handleSample(detected: detected, luminance: luminance) }
        }
        camera.onFailure = { [weak self] in
            DispatchQueue.main.async { self?.cameraState = .unavailable }
        }
        camera.start(detectsFaces: detectionMode == .face)
    }

    func stop() {
        camera.stop()
    }

    private func handleSample(detected: Bool, luminance: Double) {
        cameraState = .running
        isRoomDark = luminance < darkLuminanceThreshold

        if detected {
            misses = 0
            guard !personPresent else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                personPresent = true
                if hasSteppedAway { hasComeBack = true }
            }
        } else {
            misses += 1
            guard personPresent, misses >= missesBeforeAway else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                personPresent = false
                hasSteppedAway = true
            }
        }
    }
}

// MARK: - Camera

/// A continuously running front-camera session with a throttled Vision check. Everything but
/// `session` is touched on its own queue only.
nonisolated final class TryOutCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    var onSample: (@Sendable (_ detected: Bool, _ luminance: Double) -> Void)?
    var onFailure: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.rafapages.dashpad.tryout", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var detectsFaces = false
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var lastAnalysis = Date.distantPast
    /// Fast enough to feel live, slow enough to leave an old iPad's CPU alone.
    private let analysisInterval: TimeInterval = 0.35

    func start(detectsFaces: Bool) {
        queue.async {
            self.detectsFaces = detectsFaces
            guard self.configureIfNeeded() else {
                self.onFailure?()
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Called by the preview whenever the interface turns.
    func setOrientation(_ orientation: UIInterfaceOrientation) {
        queue.async {
            self.orientation = orientation
            self.applyOrientation()
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else { return false }

        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()

        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        applyOrientation()
        isConfigured = true
        return true
    }

    /// Same rotation as the real pipeline, so Vision sees people upright.
    private func applyOrientation() {
        guard let connection = output.connection(with: .video) else { return }
        CameraRotation.apply(orientation, to: connection, mirrored: true)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now

        let luminance = FrameLuminance.average(of: pixelBuffer)
        let request: VNImageBasedRequest = detectsFaces ? VNDetectFaceRectanglesRequest() : VNDetectHumanRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer).perform([request])
        let detected = !(request.results ?? []).isEmpty
        onSample?(detected, luminance)
    }
}

// MARK: - Preview

/// The live camera picture. Tells the camera which way the interface is facing whenever it
/// lays out, which covers rotation.
struct CameraPreview: UIViewRepresentable {
    let camera: TryOutCamera
    /// Changes once frames are arriving. The preview's connection only exists from then on, so
    /// the rotation has to be applied again.
    let isRunning: Bool

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.camera = camera
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.setNeedsLayout()
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var camera: TryOutCamera?

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The layer class is fixed above, so this cannot fail.
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let orientation = window?.windowScene?.interfaceOrientation else { return }
        if let connection = previewLayer.connection {
            CameraRotation.apply(orientation, to: connection, mirrored: false)
        }
        camera?.setOrientation(orientation)
    }
}
