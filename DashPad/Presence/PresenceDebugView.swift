import AVFoundation
import Combine
import SwiftUI
import Vision

// MARK: - Debug sections (dropped into presenceDetail's Form)

struct PresenceDebugSections: View {
    @Environment(AppSettings.self) private var settings
    @Environment(KioskManager.self) private var km
    @Bindable var viewModel: PresenceDebugViewModel

    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            CameraDebugCard(
                session: km.captureSession,
                isCameraGated: km.isCameraGated,
                faceObservations: viewModel.faceObservations
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .listRowInsets(EdgeInsets())
        }

        Section("Status") {
            statusRow("State", value: stateName)
            lightLevelRow
            statusRow("Light Threshold", value: String(format: "%.2f", settings.lightThreshold))
            statusRow("Camera", value: cameraStatus)
            statusRow("Last Sample", value: lastSampleText)
            statusRow("Faces Detected", value: "\(viewModel.faceObservations.count)")
            statusRow("Idle Timer", value: idleTimerText)
        }

        Section {
            EventLogContent(viewModel: viewModel)
        } header: {
            HStack {
                Text("Event Log")
                Spacer()
                Button("Clear") { viewModel.clearLog() }
                    .font(.caption)
                    .textCase(nil)
            }
            .textCase(nil)
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Computed status values

    private var stateName: String {
        switch km.displayState {
        case .active: "Active"
        case .idle:   km.isCameraGated ? "Idle – Dark" : "Idle – No Presence"
        }
    }

    private var cameraStatus: String {
        if km.isCameraGated { return "Off" }
        return km.presenceDetectorIsRunning ? "Running" : "Starting…"
    }

    private var lastSampleText: String {
        guard viewModel.lastSampleDate != .distantPast else { return "—" }
        let age = now.timeIntervalSince(viewModel.lastSampleDate)
        return String(format: "%.1fs ago", max(0, age))
    }

    private var idleTimerText: String {
        guard km.displayState == .active, let start = km.idleTimerStartDate else { return "—" }
        let elapsed = now.timeIntervalSince(start)
        return String(format: "%.0fs / %.0fs", elapsed, settings.idleTimeout)
    }

    // MARK: - Row builders

    @ViewBuilder
    private var lightLevelRow: some View {
        HStack {
            Text("Light Level")
            Spacer()
            HStack(spacing: 8) {
                Text(String(format: "%.2f", km.currentLightLevel))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(km.currentLightLevel >= settings.lightThreshold ? .green : .red)
                LightLevelBar(level: km.currentLightLevel, threshold: settings.lightThreshold)
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Camera preview card

private struct CameraDebugCard: View {
    let session: AVCaptureSession?
    let isCameraGated: Bool
    let faceObservations: [VNFaceObservation]

    var body: some View {
        ZStack {
            Color.black

            if !isCameraGated, let session {
                // Face overlays are drawn in UIKit so layerRectConverted handles
                // all rotation/gravity math automatically.
                AVPreviewView(session: session, faceObservations: faceObservations)

                // LIVE badge stays in SwiftUI — simple corner overlay.
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                    }
                    Spacer()
                }
            } else {
                Text("Camera OFF — dark room")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AVCaptureSession preview (UIViewRepresentable)

private struct AVPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let faceObservations: [VNFaceObservation]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> _View {
        let v = _View()
        v.previewLayer.videoGravity = .resizeAspect
        v.previewLayer.session = session
        context.coordinator.attach(to: v.previewLayer, session: session)
        return v
    }

    func updateUIView(_ uiView: _View, context: Context) {
        uiView.updateFaceOverlays(faceObservations)
    }

    static func dismantleUIView(_ uiView: _View, coordinator: Coordinator) {
        coordinator.detach()
        uiView.previewLayer.session = nil
    }

    // MARK: Coordinator — tracks interface orientation and updates videoRotationAngle

    final class Coordinator: NSObject {
        private var sessionObservation: NSKeyValueObservation?
        private weak var previewLayer: AVCaptureVideoPreviewLayer?

        func attach(to layer: AVCaptureVideoPreviewLayer, session: AVCaptureSession) {
            previewLayer = layer
            applyRotation(to: layer)

            sessionObservation = session.observe(\.isRunning, options: .new) { [weak self] _, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let layer = self?.previewLayer else { return }
                    self?.applyRotation(to: layer)
                }
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }

        func detach() {
            sessionObservation = nil
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func orientationDidChange() {
            guard let layer = previewLayer else { return }
            applyRotation(to: layer)
        }

        private func applyRotation(to layer: AVCaptureVideoPreviewLayer) {
            guard let connection = layer.connection else { return }
            let angle = rotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = legacyOrientation()
            }
        }

        private func rotationAngle() -> CGFloat {
            switch currentInterfaceOrientation() {
            case .portrait:           return 90
            case .portraitUpsideDown: return 270
            case .landscapeRight:     return 180
            case .landscapeLeft:      return 0
            default:                  return 90
            }
        }

        private func legacyOrientation() -> AVCaptureVideoOrientation {
            switch currentInterfaceOrientation() {
            case .portrait:           return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeRight:     return .landscapeRight
            case .landscapeLeft:      return .landscapeLeft
            default:                  return .portrait
            }
        }

        private func currentInterfaceOrientation() -> UIInterfaceOrientation {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.interfaceOrientation ?? .portrait
        }
    }

    // MARK: UIView — preview layer + CALayer face overlays

    final class _View: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private let overlayLayer = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(overlayLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            overlayLayer.frame = layer.bounds
        }

        func updateFaceOverlays(_ observations: [VNFaceObservation]) {
            overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

            for obs in observations {
                // Vision uses bottom-left origin; metadata output rect uses top-left.
                let metaRect = CGRect(
                    x: obs.boundingBox.minX,
                    y: 1 - obs.boundingBox.maxY,
                    width: obs.boundingBox.width,
                    height: obs.boundingBox.height
                )
                // layerRectConverted handles videoRotationAngle + videoGravity for us.
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)

                let box = CAShapeLayer()
                box.path = UIBezierPath(rect: rect).cgPath
                box.strokeColor = UIColor.green.cgColor
                box.fillColor = UIColor.clear.cgColor
                box.lineWidth = 2
                overlayLayer.addSublayer(box)

                let label = CATextLayer()
                label.string = String(format: "%.2f", obs.confidence)
                label.fontSize = 11
                label.foregroundColor = UIColor.green.cgColor
                label.backgroundColor = UIColor.black.withAlphaComponent(0.65).cgColor
                label.alignmentMode = .center
                label.contentsScale = UIScreen.main.scale
                label.frame = CGRect(x: rect.minX, y: max(2, rect.minY - 18), width: 44, height: 16)
                overlayLayer.addSublayer(label)
            }
        }
    }
}

// MARK: - Light level bar

private struct LightLevelBar: View {
    let level: Double
    let threshold: Double

    private let maxDisplay: Double = 0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.25))
                RoundedRectangle(cornerRadius: 2)
                    .fill(level >= threshold ? Color.green : Color.red)
                    .frame(width: geo.size.width * min(level / maxDisplay, 1.0))
            }
        }
        .frame(width: 48, height: 6)
    }
}

// MARK: - Event log content

private struct EventLogContent: View {
    @Bindable var viewModel: PresenceDebugViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.logEntries) { entry in
                            HStack(alignment: .top, spacing: 0) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.secondary)
                                Text("  \(entry.message)")
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("log-bottom")
                    }
                    .onChange(of: viewModel.logEntries.count) { _, _ in
                        withAnimation { proxy.scrollTo("log-bottom") }
                    }
                }
            }
            .frame(height: 180)

            Divider()

            Toggle("Verbose (frame events)", isOn: $viewModel.verboseFrameEvents)
                .font(.subheadline)
        }
    }
}
