import AVFoundation
import SwiftUI
import UIKit

enum DisplayState {
    case active, idle
}

@Observable
class KioskManager {
    var displayState: DisplayState = .idle
    var showingPINEntry = false
    var showingSettings = false
    var isKioskModeActive = false

    var debugViewModel: PresenceDebugViewModel?
    private(set) var currentLightLevel: Double = 0
    private(set) var isCameraGated: Bool = true
    private(set) var idleTimerStartDate: Date?

    var captureSession: AVCaptureSession? { presenceDetector?.captureSession }
    var presenceDetectorIsRunning: Bool { presenceDetector?.captureSession?.isRunning ?? false }

    private var settings: AppSettings?
    private var presenceDetector: PresenceDetector?
    private var lightMonitor: LightMonitor?
    private var idleTimer: Timer?
    private var started = false

    // MARK: - Lifecycle

    func start(settings: AppSettings) {
        guard !started else { return }
        started = true
        self.settings = settings

        presenceDetector = PresenceDetector()
        lightMonitor = LightMonitor()

        presenceDetector?.onPresenceDetected = { [weak self] detected in
            self?.handlePresenceDetection(detected)
        }

        presenceDetector?.onFrameResult = { [weak self] observations in
            self?.debugViewModel?.frameProcessed(observations: observations)
        }

        lightMonitor?.onBrightnessChanged = { [weak self] brightness in
            self?.handleBrightnessChange(brightness)
        }

        lightMonitor?.start()
    }

    // MARK: - Secret gesture → PIN prompt

    func handleSecretTap() {
        guard !showingPINEntry, !showingSettings else { return }
        showingPINEntry = true
    }

    /// Length of the stored PIN (0 if unset). Used by the overlay for auto-validation timing.
    var storedPINLength: Int { settings?.exitPIN.count ?? 0 }

    /// Returns true if PIN matches (or no PIN is set).
    func validatePIN(_ entered: String) -> Bool {
        guard let settings else { return false }
        let stored = settings.exitPIN
        guard stored.isEmpty || entered == stored else { return false }
        showingPINEntry = false
        if isKioskModeActive { deactivateGuidedAccess() }
        showingSettings = true
        return true
    }

    func dismissSettings() {
        showingSettings = false
    }

    // MARK: - Guided Access

    func activateKioskMode() {
        UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] success in
            DispatchQueue.main.async { self?.isKioskModeActive = success }
        }
    }

    private func deactivateGuidedAccess() {
        UIAccessibility.requestGuidedAccessSession(enabled: false) { [weak self] success in
            DispatchQueue.main.async { if success { self?.isKioskModeActive = false } }
        }
    }

    // MARK: - Presence pipeline

    private func handleBrightnessChange(_ brightness: CGFloat) {
        guard let settings else { return }
        let level = Double(brightness)
        let wasGated = isCameraGated
        currentLightLevel = level
        isCameraGated = level < settings.lightThreshold

        if level < settings.lightThreshold {
            presenceDetector?.stop()
            transitionToIdle()
            if !wasGated {
                debugViewModel?.addEvent(String(format: "⚡  Camera OFF — below light threshold (%.2f)", level))
            }
        } else {
            presenceDetector?.start(sampleInterval: settings.cameraSampleRate, detectionMode: settings.detectionMode)
            if wasGated {
                debugViewModel?.addEvent(String(format: "⚡  Camera ON — above light threshold (%.2f)", level))
            }
        }
    }

    private func handlePresenceDetection(_ detected: Bool) {
        if detected {
            transitionToActive()
            scheduleIdleTimer()
        }
    }

    private var mainScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    private func transitionToActive() {
        guard displayState != .active else { return }
        debugViewModel?.addEvent("→  Active (face detected)")
        withAnimation(.easeInOut(duration: 0.4)) { displayState = .active }
        if let b = settings?.activeBrightness {
            mainScreen?.brightness = b
        }
    }

    private func transitionToIdle() {
        guard displayState != .idle else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        idleTimerStartDate = nil
        withAnimation(.easeInOut(duration: 0.6)) { displayState = .idle }
        if let b = settings?.idleBrightness {
            mainScreen?.brightness = b
        }
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        guard let timeout = settings?.idleTimeout else { return }
        idleTimerStartDate = Date()
        debugViewModel?.addEvent("↺  Idle timer reset")
        idleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.debugViewModel?.addEvent("→  Idle – No Presence (timeout)")
            self?.transitionToIdle()
        }
    }
}
