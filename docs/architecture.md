# Architecture

This document describes how DashPad is structured and how its major components interact. It is written for a developer who is reading the codebase for the first time and wants to understand where things live and why before making changes.

---

## Guiding principles

**Single coordinator, dumb components.** `KioskManager` is the only class that knows about the overall app state. Views and detectors are given narrow responsibilities and report results upward rather than making decisions themselves.

**No third-party dependencies.** The entire app is built on Apple system frameworks. This is a deliberate constraint - it keeps the build simple, the binary small, and the privacy claims verifiable.

**Settings flow down, never up.** `AppSettings` is the single source of truth for configuration. It is injected into the SwiftUI environment at the root and read directly by any component that needs it. Nothing writes to `AppSettings` except the settings UI.

**Privacy by construction.** The camera pipeline is designed so that frames cannot accidentally persist - the session tears down after every sample, the buffer is released with the session, and the only in-memory copy is the optional debug image which exists only while the debug UI is open.

---

## Source structure

```
DashPad/
├── DashPadApp.swift          @main entry point; injects AppSettings and KioskManager
│
├── AppSettings.swift         All user configuration; UserDefaults persistence; Keychain for PIN
├── KioskManager.swift        Central coordinator; presence state machine; display transitions
├── ContentView.swift         Root view; switches between KioskBrowserView and IdleView
│
├── Kiosk/
│   └── KioskBrowserView.swift   WKWebView wrapper; navigation policy; reload
│
├── Presence/
│   ├── PresenceDetector.swift   AVCaptureSession; luminance check; Vision request; CaptureResult
│   ├── PresenceDebugView.swift  Debug overlay: last frame, bounding boxes, event log
│   └── PresenceDebugViewModel.swift  Observable state for the debug UI
│
├── Idle/
│   ├── IdleView.swift        Switches between clock, blank, and custom URL modes
│   └── ClockView.swift       Digital and analogue clock implementations
│
└── Settings/
    ├── SettingsView.swift    NavigationSplitView settings panel; all settings sections
    ├── PINEntryOverlay.swift PIN entry (exit kiosk) and PIN setup (change PIN)
    └── [secret gesture]      Triple-tap corner target embedded in ContentView
```

---

## Environment objects

Two objects are injected at the root in `DashPadApp.swift` and available throughout the view hierarchy via `@EnvironmentObject`:

**`AppSettings`** - an `ObservableObject`. Every setting is an `@Published` stored property with a `didSet` observer that writes to `UserDefaults`. The exit PIN is the only exception: it is written to and read from Keychain via `KeychainHelper`. Views bind to `AppSettings` properties through the projected `$settings` wrapper.

**`KioskManager`** - an `ObservableObject`. Views read its published state (`displayState`, `showingPINEntry`, `showingSettings`) to decide what to render. Views do not write to `KioskManager` directly except via its public methods (`handleSecretTap()`, `validatePIN()`, `activateKioskMode()`, etc.).

Not every property on `KioskManager` is `@Published`. `ObservableObject` invalidates every observing view on any published change, so state that churns but is never rendered is deliberately left unpublished: `lastLuminance` is rewritten on every camera sample, and `manualWakeUntil` is internal to the schedule state machine. The debug overlay reads its own copy of the luminance from `PresenceDebugViewModel` rather than from `KioskManager`.

Neither object is a singleton in the Swift sense - they are instantiated once in `DashPadApp` as `@StateObject` properties and live for the lifetime of the app.

---

## View hierarchy

```
DashPadApp
└── ContentView
    ├── KioskBrowserView          (when displayState == .active)
    │   └── WebViewRepresentable  (UIViewRepresentable wrapping WKWebView)
    ├── IdleView                  (when displayState == .idle)
    │   ├── ClockView             (idleScreenType == .clock)
    │   ├── Color.black           (idleScreenType == .blank)
    │   └── IdleWebView           (idleScreenType == .customURL)
    ├── [corner tap target]       (invisible, always present)
    └── PINEntryOverlay           (when showingPINEntry == true, zIndex: 10)

ContentView.sheet → SettingsView  (when showingSettings == true)
```

`ContentView` is deliberately thin. It contains no logic beyond reading `KioskManager.displayState` and rendering the appropriate branch. The corner tap target is an invisible `Color.clear` rectangle sitting in the bottom-right of the safe area - `onTapGesture(count: 3)` calls `KioskManager.handleSecretTap()`.

---

## KioskManager in detail

`KioskManager` is the most complex class in the app. It has three distinct responsibilities:

### 1. Lifecycle and presence modes

`start(settings:)` is called from `ContentView` — from `onAppear` when onboarding has already been completed, otherwise from the onboarding sheet's completion handler. It is never called while onboarding is on screen: the camera pipeline would raise the system permission dialog behind the sheet and dim the display to the idle brightness mid-setup. It reads `AppSettings.presenceMode` and dispatches to the appropriate mode:

```swift
switch settings.presenceMode {
case .automatic:    startPresencePipeline()   // camera + Vision
case .schedule:     startScheduleTimer()       // time-based, no camera
case .alwaysActive: transitionDisplay(to: .active)
}
```

`setPresenceMode(_:)` performs a clean teardown of the current mode before starting the new one - it stops the schedule timer, cancels all camera timers, and releases `PresenceDetector`.

**Camera mode** is driven by three `Timer` properties:

```swift
private var sampleTimer: Timer?     // idle → sampling
private var recheckTimer: Timer?    // active → rechecking  
private var countdownTimer: Timer?  // countingDown → idle
```

Every state transition calls `cancelAllTimers()` first, then starts only the timer(s) appropriate for the new state. When a timer fires, `KioskManager` calls `PresenceDetector.captureOnce()`. The result arrives on the main thread via `onCaptureResult` and is processed by `handleCaptureResult(_:)`.

**Schedule mode** uses a single 60-second repeating timer that calls `evaluateSchedule()`. That method checks the current time against the active windows in `AppSettings.weeklySchedule`, respects any in-progress `manualWakeUntil` override, and calls `transitionDisplay(to:)` with the result. `evaluateSchedule()` is also called on `applicationDidBecomeActive` (wired in `ContentView` via `NotificationCenter`) to catch transitions that happened while the app was backgrounded.

See [presence-pipeline.md](presence-pipeline.md) for the full camera state machine and schedule data model documentation.

### 2. PIN and settings access

The secret gesture flow:

1. Triple-tap fires `KioskManager.handleSecretTap()`
2. If no PIN is set (`storedPINLength == 0`), `showingSettings = true` directly
3. If a PIN is set, `showingPINEntry = true`
4. `PINEntryOverlay` calls `KioskManager.validatePIN(_:)`
5. On success, `showingPINEntry = false`, `showingSettings = true`
6. `SettingsView` calls `KioskManager.dismissSettings()` when done

Biometric recovery is available via `recoverWithBiometrics()`, which uses `LAContext` with `.deviceOwnerAuthentication` (Face ID, Touch ID, or device passcode).

### 3. Display and brightness

`transitionDisplay(to:)` is the single place where `displayState` changes. It applies a SwiftUI animation and sets `UIScreen` brightness via the active `UIWindowScene`. Active and idle brightness values are read from `AppSettings` at transition time.

---

## KioskBrowserView in detail

`WebViewRepresentable` creates the `WKWebView` once in `makeUIView(context:)`. It is not recreated when `AppSettings` changes - the WebView is long-lived for the duration of the app.

### Script injection

`injectUserScripts(into:)` is called during `WKWebViewConfiguration` setup (before the `WKWebView` is created). It injects two things:

1. A hardcoded kiosk CSS block that disables text selection and touch callouts on all elements.
2. The user's custom CSS and custom JS from `AppSettings`, if non-empty.

All CSS is injected as JavaScript that creates a `<style>` element and appends it to `<head>`. The CSS string is escaped for embedding in a JS string literal before injection. Scripts are registered with `.atDocumentEnd` injection time so that `document.head` exists when they run.

Because scripts are added to the `WKWebViewConfiguration` before the view is created, changes to `customCSS` or `customJS` would only take effect on the next page load.

Note: the user-facing settings UI for custom CSS/JS is currently disabled. The injection plumbing remains in place but is dormant, since `customCSS` and `customJS` are always empty until that UI returns. Re-enabling custom injection is a planned (deferred) feature; see the roadmap in the README.

### Navigation policy

`Coordinator.webView(_:decidePolicyFor:)` enforces the domain allowlist from `AppSettings.allowedDomainList`. If the list is empty, all navigation is permitted. If non-empty, the request's host must exactly match or be a subdomain of a listed domain. Blocked navigations are silently cancelled.

### Reload on failure

`webView(_:didFailProvisionalNavigation:)` and `webView(_:didFail:)` both call `scheduleRetry(webView:)`, which sets a 10-second `Timer` to reload the home URL. If the connection is still down after 10 seconds, the timer fires again.

---

## AppSettings persistence

Every setting is persisted immediately on change via `didSet`. The persistence strategy per type:

| Type | Storage |
|---|---|
| `String` | `UserDefaults.set(_:forKey:)` |
| `Double` | `UserDefaults.set(_:forKey:)` |
| `Bool` | `UserDefaults.set(_:forKey:)` |
| `[String]` | `UserDefaults.set(_:forKey:)` (as `Array`) |
| `RawRepresentable` enums | `UserDefaults.set(rawValue, forKey:)` |
| `WeeklySchedule` (`Codable` struct) | JSON-encoded `Data` via `saveCodable(_:key:)` → `UserDefaults.set(_:forKey:)` |
| Exit PIN (`String`) | Keychain via `KeychainHelper` |

`KeychainHelper` is a private enum with three static methods, `read(key:)`, `write(key:value:)` and `delete(key:)`. It uses `kSecClassGenericPassword` with the item's key as `kSecAttrAccount`. On write, it deletes any existing item before adding the new one - this avoids duplicate item errors.

Keychain items outlive app deletion, so `AppSettings.init` deletes the stored PIN when `hasCompletedOnboarding` is `false`. Without this a reinstall comes back already locked by the previous install's PIN.

`UserDefaults` reads use `optionalDouble(forKey:)`, a private extension that returns `nil` if the key has never been set (rather than `0.0`, which is `UserDefaults`'s default for missing doubles). This allows the initialiser to distinguish "never configured" from "explicitly set to zero."

---

## Debug mode

`PresenceDebugViewModel` is an `ObservableObject` instantiated in `SettingsView`. When debug mode is toggled on, `SettingsView` assigns it to `KioskManager.debugViewModel`. `KioskManager` then calls `debugViewModel?.frameProcessed(...)` and `debugViewModel?.addEvent(...)` at key points in the pipeline.

When the settings sheet is dismissed, `KioskManager.debugViewModel` is set to `nil`, stopping all debug output.

`PresenceDebugSections` is a SwiftUI view embedded in the `SettingsView` presence form. It displays the last captured frame with Vision bounding boxes drawn via `Canvas`, a live status section (current state, luminance bar, timer countdown), and a scrolling event log.

The debug image (`CaptureResult.debugImage`) is a `UIImage` created from the captured `CIImage` on the session queue and passed through `CaptureResult` to the view model. It exists only in memory and only while the debug UI is open.

---

## Deployment target and back-deployment

The deployment target is iOS/iPadOS 16.0, chosen so the app runs on the older iPads its use case
depends on - an iPad 5th generation or original iPad Pro mounted on a wall is squarely the target
user. 16.0 is also where the SwiftUI surface this app is built on begins: `NavigationSplitView`,
`NavigationStack`, `scrollContentBackground`, `presentationDetents`, `LabeledContent`, `Grid` and
`UnevenRoundedRectangle` are all iOS 16.

The app is still developed against the current SDK and uses newer APIs where they exist. Anything
above the deployment target is gated, and the gates are collected in
`Support/AvailabilityCompat.swift` rather than scattered through the views:

| API | Introduced | Fallback below it |
| --- | --- | --- |
| `containerBackground(_:for:)` (navigation placements) | iOS 18 | Standard opaque container background |
| `ContentUnavailableView` | iOS 17 | `EmptyStatePlaceholder`, an icon-plus-title stack |
| `onChange(of:)` two-parameter closure | iOS 17 | `onChangeCompat(of:perform:)`, the single-parameter overload |
| `containerRelativeFrame(_:alignment:_:)` | iOS 17 | Container height measured via `ContainerHeightKey` preference |
| `AVCaptureConnection.videoRotationAngle` | iOS 17 | `videoOrientation`, mapped in `PresenceDetector.videoOrientation()` |
| `buttonStyle(.glass)` and Liquid Glass styling | iOS 26 | `LegacyCircleKeyStyle` in `PINEntryOverlay.swift` |

Two things follow from this. Adding a modifier from a recent SDK means gating it the same way -
the build fails otherwise, which is the intended safety net. And the visual result is deliberately
not identical across versions: older releases get the standard system appearance rather than a
hand-built imitation of the newer one.

Note that these fallback branches cannot be exercised on a modern simulator, which always takes
the newest path. Verifying them needs an iOS 16 or 17 runtime, or real hardware.

---

## Adding a new feature - quick guide

**New setting:** Add a property to `AppSettings` with a `didSet` persistence call, add a `Key` case to the private enum, and add the UI to the relevant section in `SettingsView`. For `Codable` types, use `saveCodable(_:key:)` / `decodeCodable(_:forKey:)` instead of the plain `save` helper.

**New idle screen mode:** Add a case to `IdleScreenType` in `AppSettings.swift`, handle it in `IdleView.swift`'s switch, and add the corresponding UI option in `SettingsView.idleScreenDetail`.

**New detection behaviour (camera mode):** The state machine is entirely in `KioskManager`. `PresenceDetector` is responsible only for capturing a frame and returning a result - it should not need changes for most behavioural modifications.

**New presence mode:** Add a case to `PresenceMode` in `AppSettings.swift`. In `KioskManager`, add teardown/setup calls to `setPresenceMode(_:)` and `start(settings:)`. Wire any new timers through `cancelAllTimers()` so they are cleaned up on mode switch.

**New WebView behaviour:** `WebViewRepresentable` and its `Coordinator` in `KioskBrowserView.swift` are the right place for anything that touches the `WKWebView` directly.
