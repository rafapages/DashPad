import AVFoundation
import LocalAuthentication
import SwiftUI
import UIKit

enum DisplayState {
    case active, idle
}

enum PresenceState {
    case idle, sampling, active, rechecking, countingDown
}

@Observable
class KioskManager {
    var displayState: DisplayState = .active
    var presenceState: PresenceState = .idle
    var showingPINEntry = false
    var showingSettings = false
    var isKioskModeActive = false

    var debugViewModel: PresenceDebugViewModel?
    private(set) var lastLuminance: Double = 0
    // Set when entering .active (recheck timer started) or .countingDown (countdown started).
    private(set) var stateTimerStartDate: Date?

    private var settings: AppSettings?
    private var presenceDetector: PresenceDetector?
    private var sampleTimer: Timer?
    private var recheckTimer: Timer?
    private var countdownTimer: Timer?
    private var lastFrameWasDark = false
    private var started = false

    // MARK: - Lifecycle

    func start(settings: AppSettings) {
        guard !started else { return }
        started = true
        self.settings = settings

        guard settings.presenceEnabled else {
            transitionDisplay(to: .active)
            return
        }

        startPresencePipeline()
    }

    // MARK: - Touch-to-wake

    func handleScreenTap() {
        guard presenceDetector != nil else { return }
        switch presenceState {
        case .idle, .sampling, .countingDown, .rechecking:
            enterActive(event: "👆  Screen tapped")
        case .active:
            break
        }
    }

    // MARK: - Secret gesture → PIN prompt

    func handleSecretTap() {
        guard !showingPINEntry, !showingSettings else { return }
        if storedPINLength == 0 {
            showingSettings = true
        } else {
            showingPINEntry = true
        }
    }

    func recoverWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Access DashPad settings") { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, success else { return }
                self.showingPINEntry = false
                if self.isKioskModeActive { self.deactivateGuidedAccess() }
                self.showingSettings = true
            }
        }
    }

    var storedPINLength: Int { settings?.exitPIN.count ?? 0 }

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

    // MARK: - Presence on/off

    func setPresenceEnabled(_ enabled: Bool) {
        if enabled {
            guard presenceDetector == nil else { return }
            startPresencePipeline()
        } else {
            cancelAllTimers()
            presenceDetector = nil
            presenceState = .idle
            transitionDisplay(to: .active)
        }
    }

    private func startPresencePipeline() {
        presenceDetector = PresenceDetector()
        presenceDetector?.onCaptureResult = { [weak self] result in
            self?.handleCaptureResult(result)
        }
        enterActive(event: "🚀  App launched")
    }

    // MARK: - State machine

    private func enterIdle() {
        cancelAllTimers()
        presenceState = .idle
        stateTimerStartDate = nil
        transitionDisplay(to: .idle)

        let rate = lastFrameWasDark
            ? (settings?.nightSampleRate ?? 60)
            : (settings?.cameraSampleRate ?? 5)

        sampleTimer = Timer.scheduledTimer(withTimeInterval: rate, repeats: false) { [weak self] _ in
            self?.sampleTimerFired()
        }
    }

    private func sampleTimerFired() {
        switch presenceState {
        case .idle:
            presenceState = .sampling
            debugViewModel?.addEvent("📷  Sampling… (warming up)")
            capture()
        case .countingDown:
            debugViewModel?.addEvent("📷  Sampling… (warming up)")
            capture()
        default:
            break
        }
    }

    private func enterActive(event: String? = nil) {
        cancelAllTimers()
        presenceState = .active
        stateTimerStartDate = Date()
        transitionDisplay(to: .active)

        let interval = settings?.presenceRecheckInterval ?? 30
        let message = event ?? "✅  Still present"
        debugViewModel?.addEvent(String(format: "%@ — recheck in %.0fs", message, interval))

        recheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.recheckTimerFired()
        }
    }

    private func recheckTimerFired() {
        guard presenceState == .active else { return }
        presenceState = .rechecking
        debugViewModel?.addEvent("🔍  Rechecking… (warming up)")
        capture()
    }

    private func enterCountingDown() {
        cancelAllTimers()
        presenceState = .countingDown
        stateTimerStartDate = Date()
        // displayState stays .active — dashboard remains visible during the countdown.

        let timeout = settings?.idleTimeout ?? 60
        countdownTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.countdownTimerFired()
        }

        scheduleSampleTimerForCountdown()
    }

    private func scheduleSampleTimerForCountdown() {
        let rate = settings?.cameraSampleRate ?? 5
        sampleTimer = Timer.scheduledTimer(withTimeInterval: rate, repeats: false) { [weak self] _ in
            self?.sampleTimerFired()
        }
    }

    private func countdownTimerFired() {
        guard presenceState == .countingDown else { return }
        let rate = lastFrameWasDark
            ? (settings?.nightSampleRate ?? 60)
            : (settings?.cameraSampleRate ?? 5)
        debugViewModel?.addEvent(String(format: "💤  Timeout — next sample in %.0fs", rate))
        lastFrameWasDark = false
        enterIdle()
    }

    // MARK: - Capture + result handling

    private func capture() {
        guard let settings else { return }
        presenceDetector?.captureOnce(
            detectionMode: settings.detectionMode,
            darkLuminanceThreshold: settings.darkLuminanceThreshold
        )
    }

    private func handleCaptureResult(_ result: CaptureResult) {
        lastLuminance = result.luminance
        let isDark = result.luminance < (settings?.darkLuminanceThreshold ?? 20)
        lastFrameWasDark = isDark
        let personDetected = !result.observations.isEmpty

        debugViewModel?.frameProcessed(
            luminance: result.luminance,
            observations: result.observations,
            image: result.debugImage
        )

        switch presenceState {
        case .sampling:
            if isDark {
                let nightRate = settings?.nightSampleRate ?? 60
                debugViewModel?.addEvent(String(format: "🌙  Dark (lum %.0f) — next sample in %.0fs (night rate)", result.luminance, nightRate))
                enterIdle()
            } else if personDetected {
                let mode = settings?.detectionMode.displayName ?? "body"
                enterActive(event: "✅  Active (\(mode) detected)")
            } else {
                let dayRate = settings?.cameraSampleRate ?? 5
                debugViewModel?.addEvent(String(format: "📷  No detection (lum %.0f) — next sample in %.0fs", result.luminance, dayRate))
                enterIdle()
            }

        case .rechecking:
            if personDetected {
                enterActive()
            } else {
                let timeout = settings?.idleTimeout ?? 60
                let reason = isDark ? "dark" : "no presence"
                debugViewModel?.addEvent(String(format: "⏱  %@ (lum %.0f) — %.0fs countdown started", reason, result.luminance, timeout))
                enterCountingDown()
            }

        case .countingDown:
            if isDark {
                debugViewModel?.addEvent(String(format: "🌙  Dark (lum %.0f) during countdown — going idle", result.luminance))
                enterIdle()
            } else if personDetected {
                enterActive(event: "✅  Active (returned)")
            } else {
                let elapsed = stateTimerStartDate.map { Date().timeIntervalSince($0) } ?? 0
                let remaining = max(0, (settings?.idleTimeout ?? 60) - elapsed)
                debugViewModel?.addEvent(String(format: "⏱  No detection (lum %.0f) — %.0fs remaining", result.luminance, remaining))
                scheduleSampleTimerForCountdown()
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private func cancelAllTimers() {
        sampleTimer?.invalidate();    sampleTimer = nil
        recheckTimer?.invalidate();   recheckTimer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
    }

    private func transitionDisplay(to state: DisplayState) {
        guard displayState != state else { return }
        withAnimation(.easeInOut(duration: state == .active ? 0.4 : 0.6)) { displayState = state }
        let brightness = state == .active ? settings?.activeBrightness : settings?.idleBrightness
        if let b = brightness { mainScreen?.brightness = b }
    }

    private var mainScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }
}
