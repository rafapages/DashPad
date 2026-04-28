// KioskManager.swift — central coordinator for the app.
// Owns the active presence mode (camera pipeline, schedule timer, or always-active),
// drives the active/idle display state machine, and manages the PIN/settings access flow.
// Injected into the SwiftUI environment; views call its public methods rather than
// modifying state directly.

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
    private(set) var stateTimerStartDate: Date?
    /// Non-nil while a tap-to-wake is in progress in Schedule mode. Cleared by
    /// `evaluateSchedule()` once the date is passed, or when the mode changes.
    private(set) var manualWakeUntil: Date? = nil

    private var settings: AppSettings?
    private var presenceDetector: PresenceDetector?
    private var sampleTimer: Timer?
    private var recheckTimer: Timer?
    private var countdownTimer: Timer?
    private var scheduleTimer: Timer?
    private var lastFrameWasDark = false
    private var started = false

    // MARK: - Lifecycle

    /// Called once from `ContentView.onAppear`. Starts the presence pipeline appropriate
    /// for the current `presenceMode`. Subsequent mode changes go through `setPresenceMode(_:)`.
    func start(settings: AppSettings) {
        guard !started else { return }
        started = true
        self.settings = settings

        switch settings.presenceMode {
        case .automatic:    startPresencePipeline()
        case .schedule:     startScheduleTimer()
        case .alwaysActive: transitionDisplay(to: .active)
        }
    }

    // MARK: - Schedule mode

    /// Checks whether the current time falls inside an Active window and transitions
    /// the display accordingly. Called every 60 s by the schedule timer and also on
    /// `applicationDidBecomeActive` to catch transitions that occurred while backgrounded.
    func evaluateSchedule() {
        guard let settings, settings.presenceMode == .schedule else { return }

        if let until = manualWakeUntil {
            if Date() < until {
                transitionDisplay(to: .active)
                return
            } else {
                manualWakeUntil = nil
            }
        }

        let calendar = Calendar.current
        let now = Date()
        let minuteOfDay = calendar.component(.hour, from: now) * 60
                        + calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now) - 1 // 0-indexed

        let windows: [ScheduleWindow]
        if settings.weeklySchedule.sameEveryDay {
            windows = settings.weeklySchedule.windows[0]
        } else {
            windows = settings.weeklySchedule.windows[weekday]
        }

        let shouldBeActive = windows.contains { $0.isActive(at: minuteOfDay) }
        transitionDisplay(to: shouldBeActive ? .active : .idle)
    }

    /// Wakes the display temporarily in response to a tap on the idle screen while in
    /// Schedule mode. Each call pushes `manualWakeUntil` forward; the next timer tick
    /// will clear it and return to the schedule-driven state if it has expired.
    func manualWake() {
        guard let settings, settings.presenceMode == .schedule else { return }
        guard displayState == .idle else { return }
        manualWakeUntil = Date().addingTimeInterval(settings.manualWakeTimeout)
        transitionDisplay(to: .active)
    }

    private func startScheduleTimer() {
        evaluateSchedule()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateSchedule()
        }
    }

    private func stopScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        manualWakeUntil = nil
    }

    // MARK: - Presence mode switch

    /// Tears down the current presence mode and starts the new one. Safe to call at any time.
    func setPresenceMode(_ mode: PresenceMode) {
        stopScheduleTimer()
        cancelAllTimers()
        presenceDetector = nil
        presenceState = .idle

        switch mode {
        case .automatic:    startPresencePipeline()
        case .schedule:     startScheduleTimer()
        case .alwaysActive: transitionDisplay(to: .active)
        }
    }

    // MARK: - Touch-to-wake (camera mode)

    /// Wakes the display from idle in response to a screen tap. Only acts in Automatic
    /// (camera) mode — the presence detector must be active. For Schedule mode use `manualWake()`.
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

    /// Called by the invisible triple-tap target in the bottom-right corner.
    /// Opens settings directly if no PIN is set; otherwise shows the PIN entry overlay.
    func handleSecretTap() {
        guard !showingPINEntry, !showingSettings else { return }
        if storedPINLength == 0 {
            showingSettings = true
        } else {
            showingPINEntry = true
        }
    }

    /// Fallback for a forgotten PIN. Uses Face ID / Touch ID / device passcode via
    /// `LAContext` with `.deviceOwnerAuthentication`, which includes the system passcode.
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

    /// Returns `true` and opens settings if the entered PIN matches the stored one
    /// (or if no PIN has been set). Returns `false` and leaves the overlay visible otherwise.
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

    // MARK: - Camera presence pipeline

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
        // Active is slightly snappier (0.4 s) — the user just arrived and wants the screen now.
        // Idle is a touch slower (0.6 s) — a gradual fade feels more natural when the room empties.
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
