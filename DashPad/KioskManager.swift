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

        presenceDetector?.onFaceDetected = { [weak self] detected in
            self?.handleFaceDetection(detected)
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
        if brightness < settings.lightThreshold {
            // Dark room — stop camera, go idle
            presenceDetector?.stop()
            transitionToIdle()
        } else {
            // Lit room — run camera at configured rate
            presenceDetector?.start(sampleInterval: settings.cameraSampleRate)
        }
    }

    private func handleFaceDetection(_ detected: Bool) {
        if detected {
            transitionToActive()
            scheduleIdleTimer()
        }
    }

    private func transitionToActive() {
        guard displayState != .active else { return }
        withAnimation(.easeInOut(duration: 0.4)) { displayState = .active }
        if let b = settings?.activeBrightness {
            UIScreen.main.brightness = b
        }
    }

    private func transitionToIdle() {
        guard displayState != .idle else { return }
        withAnimation(.easeInOut(duration: 0.6)) { displayState = .idle }
        if let b = settings?.idleBrightness {
            UIScreen.main.brightness = b
        }
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        guard let timeout = settings?.idleTimeout else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.transitionToIdle()
        }
    }
}
