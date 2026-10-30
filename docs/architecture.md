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
│   ├── KioskBrowserView.swift   WKWebView wrapper; navigation policy; reload; load-failure state
│   └── WebViewController.swift  Observable handle on the WebView (zoom, back, load failure)
│
├── Presence/
│   ├── PresenceDetector.swift   AVCaptureSession; luminance check; Vision request; CaptureResult
│   ├── PresenceDebugView.swift  Debug overlay: last frame, bounding boxes, event log
│   └── PresenceDebugViewModel.swift  Observable state for the debug UI
│
├── Idle/
│   ├── IdleView.swift        Switches between clock, photos, blank, and custom URL modes
│   ├── ClockView.swift       Idle clock (TimelineView); ClockFaceView switches on clockStyle; Dark Digital/Analog faces
│   ├── Clocks/
│   │   ├── ClockTheme.swift      ClockTheme and each face's hand-tuned colour table
│   │   ├── ClockTypeface.swift   Typeface setting, per-face default design/weight, ClockFont
│   │   ├── ClockOptions.swift    Per-face options and 12/24-hour format (Codable, tolerant decoding)
│   │   ├── ClockTime.swift       Hour in the chosen 12/24-hour style, date labels
│   │   ├── ClockCanvas.swift     1180×820 design canvas scaled to fit, background fill, burn-in shift
│   │   ├── ClockPhrase.swift     Time in words for the Words face (English, Spanish)
│   │   ├── ClockPickers.swift    Style thumbnails and theme swatches (Settings and onboarding)
│   │   └── NumeralsClockFace.swift, TilesClockFace.swift, WordsClockFace.swift,
│   │       HalvesClockFace.swift, SweepClockFace.swift, DotsClockFace.swift
│   └── Photos/
│       ├── IdlePhotos.swift          IdlePhoto, PhotoOptions, AppSettings add/remove helpers
│       ├── IdlePhotoStore.swift      Photo copies on disk: import, thumbnails, decoding for display
│       ├── IdlePhotoPicker.swift     System photo picker, importer, thumbnail grid (Settings and onboarding)
│       └── PhotoSlideshowView.swift  Slideshow driver, UIKit crossfade and drift, clock overlay
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
    │   ├── ClockView             (idleScreenType == .clock, or .photos with no photos yet)
    │   ├── PhotoSlideshowView    (idleScreenType == .photos)
    │   │   └── SlideshowUIView   (UIView: crossfade and slow zoom/pan in Core Animation)
    │   ├── Color.black           (idleScreenType == .blank)
    │   └── IdleWebPage           (idleScreenType == .customURL, display-only)
    │       └── IdleWebView       (UIViewRepresentable wrapping its own WKWebView)
    ├── [corner tap target]       (invisible, always present)
    └── PINEntryOverlay           (when showingPINEntry == true, zIndex: 10)

ContentView.sheet → SettingsView  (when showingSettings == true)
```

`ContentView` is deliberately thin. It contains no logic beyond reading `KioskManager.displayState` and rendering the appropriate branch. The corner tap target is an invisible `Color.clear` rectangle sitting in the bottom-right of the safe area - `onTapGesture(count: 3)` calls `KioskManager.handleSecretTap()`.

Both top-level sheets - `SettingsView` and `OnboardingView` - declare their size explicitly with
`centredSheetSizing()` (`CentredSheetSizing`, an 800x640 `PresentationSizing`, on iOS 18+) rather
than taking whatever the current release defaults to. Sheet sizing has moved twice: the narrow,
centred *form* sheet became the iPad default in iPadOS 18, iPadOS 27 extended it to sheets that
used to come up page-sized, and `.page` now fills the screen. A form sheet is narrow enough to
report a compact horizontal size class, which collapses `SettingsView`'s `NavigationSplitView`
into a single stacked column; a full-screen sheet is far more than a settings panel needs. 800pt
keeps the sidebar beside the detail pane and matches the panel the app presented before iPadOS 27.
For the same reason neither sheet uses `presentationDetents`: detents are a compact-height
mechanism, and on iPad they now shrink the sheet instead of being ignored.

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

The system Auto-Lock is kept out of the way separately: `ContentView` sets `UIApplication.shared.isIdleTimerDisabled` from `AppSettings.preventAutoLock` (on by default) on appear, whenever the setting changes, and again on every `didBecomeActive`. Without it the iPad would sleep and lock after the Auto-Lock interval regardless of presence or schedule; dimming on idle is DashPad's job, not the system's.

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

Every load of the home URL goes through `WebViewController.goHome(url:)`, which records the returned `WKNavigation` as `homeNavigation`. That lets the failure handler tell a failed dashboard load apart from a failed link.

`webView(_:didFailProvisionalNavigation:)` and `webView(_:didFail:)` both go through `handleFailure(_:navigation:provisional:)`, which works through these rules in order:

- **Abandoned, not failed.** `LoadFailure.isAbandonedLoad(_:)`: `NSURLErrorCancelled` (superseded by a newer navigation) and WebKit errors 101 (a link to a scheme the WebView can't open, such as `mailto:`), 102 (cancelled by the allowlist policy) and 204 (media handed to the system player) are ignored.
- **Failed link, page still showing.** A provisional failure that isn't the home navigation, while a page is already loaded, is ignored too, so the working dashboard stays usable.
- **Anything else.** Sets `WebViewController.loadFailure`, which `KioskBrowserView` renders as a "Can't reach dashboard" placeholder with an Open Settings button, and schedules a reload of the home URL after `WebViewController.retryInterval` (10 seconds). The URL on that screen goes through `LoadFailure.displayString(for:)`, which removes credentials, query and fragment, because the screen is visible to anyone in the room. For the same reason Open Settings calls `KioskManager.handleSecretTap()`, the corner gesture's path, so a PIN still has to be entered.

`webView(_:didFinish:)` clears `loadFailure` and cancels any pending retry, so a successful navigation is never followed by a jump back to the home URL.

If the allowlist blocks the home URL's own host, `decidePolicyFor` sets a `loadFailure` with `willRetry: false`, since retrying can't help. `KioskBrowserView` reloads the dashboard when Allowed Domains changes.

If iOS terminates the web content process (`webViewWebContentProcessDidTerminate`), the dashboard is reloaded from the home URL.

### Idle screen web page

Custom URL mode uses its own WKWebView (`IdleWebPage` / `IdleWebView` in `IdleView.swift`), separate from the dashboard's:

- **Display-only.** `.allowsHitTesting(false)` means the page never receives touches. Every tap reaches `ContentView`'s idle tap handler and wakes the dashboard, and nobody can follow a link away from the idle URL. For that reason the domain allowlist is not applied to it.
- **Short-lived.** It is created each time the display goes idle and torn down on wake, so each idle period starts fresh from `idleCustomURL`. It shares the default website data store with the dashboard, so a Home Assistant session signed in on the dashboard also works on the idle page.
- **Autoplay.** Inline media plays without a user gesture, for slideshows and camera feeds.
- **Failures.** Uses the same `LoadFailure` helpers as the dashboard: abandoned loads are ignored, anything else shows "Can't load idle screen" and retries the idle URL after `WebViewController.retryInterval`. A terminated web content process reloads the idle URL.

`AppSettings.idleWebURL` is nil unless `idleCustomURL` parses through `AppSettings.webURL(from:)` (http or https, with a host). In that case `IdleView` shows the clock, and Settings shows a warning under the URL field. Onboarding uses the same check.

### Clock faces

Every face is laid out in a fixed 1180×820 design space (iPad landscape). `ClockCanvas` works out the scale that fits its container and hands it to the face, which multiplies every dimension by it. This is used instead of `scaleEffect`, so text is drawn at its on-screen size and stays sharp when the scale goes above 1. The face's background colour fills whatever the canvas doesn't cover (portrait, other aspect ratios). The same view draws the idle screen, the Settings preview and the style thumbnails. Each face takes plain inputs (date, colours, typeface, options, scale), so thumbnails can show a fixed time.

The themed faces read colours from per-face tables in `ClockTheme.swift`. Adding a theme means one case plus one row per table. The chosen theme is stored per face (`AppSettings.clockThemes`); a face without a choice uses its designed `ClockStyle.defaultTheme`. Dark Digital and Dark Analog ignore theme, typeface and options; on the idle screen they are drawn at their original fixed size, not fitted to the canvas. `ClockView` redraws with `TimelineView`: every second only for faces that move every second (Numerals with its seconds hand, Sweep), and on the minute for the rest. On the idle screen, themed faces jump up to ±6 design points every 10 minutes to avoid OLED burn-in.

### Photos

Photos are picked with `PHPickerViewController`, which runs out of process and returns only what was picked, so DashPad never asks for photo library permission. Each one is copied into `Application Support/IdlePhotos/` as a JPEG no larger than the biggest iPad screen (2752 px), upright and in standard dynamic range; `AppSettings.idlePhotos` stores only their IDs. Copies rather than library references, because a reference needs full library access and breaks when the original is deleted or offloaded to iCloud. The folder is excluded from backups, in line with PRIVACY.md. Files that no setting refers to are deleted at launch.

`PhotoSlideshowView` decodes one photo at a time off the main thread and hands it to `SlideshowUIView`. One photo stays up, drifting back and forth; two or more advance on a timer, crossfading. The crossfade and the drift (a slow zoom with a slight pan, against burn-in) are UIKit animations, so Core Animation runs them in the render server and the app does no per-frame work between photos. The position in the loop is remembered between idle periods (not across launches), so each idle period continues rather than restarting at the first photo.

### App Transport Security

Most of the Info.plist is generated from `INFOPLIST_KEY_*` build settings, but those cannot express nested dictionaries, so `DashPad-Info.plist` at the repository root holds the one key that needs it: `NSAppTransportSecurity` → `NSAllowsArbitraryLoadsInWebContent = YES`. Xcode merges it with the generated keys. It lives outside the synchronized `DashPad/` folder so it is not also copied as a resource.

The key lets `WKWebView` load plain-HTTP dashboards on any hostname (e.g. `http://ha.home.lan:8123`). Without it, default ATS only allows plain HTTP to IP addresses, single-label hostnames and `.local` names. It applies to web content only; any native networking keeps the default ATS policy.

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

The deployment target is iOS/iPadOS 15.0, chosen so the app runs on the older iPads its use case
depends on - an iPad Air 2 or iPad 5th generation mounted on a wall is squarely the target user.
Much of the SwiftUI surface this app is built on (`NavigationSplitView`, `NavigationStack`,
`LabeledContent`, `UnevenRoundedRectangle`, `scrollContentBackground`) begins at iOS 16, so those
are gated like everything else newer than the target.

The app is still developed against the current SDK and uses newer APIs where they exist. Anything
above the deployment target is gated, and the gates are collected in
`Support/AvailabilityCompat.swift` rather than scattered through the views:

| API | Introduced | Fallback below it |
| --- | --- | --- |
| `containerBackground(_:for:)` (navigation placements) | iOS 18 | Standard opaque container background |
| `presentationSizing(_:)` with `CentredSheetSizing` | iOS 18 | Page-sized sheet is already the default on 15-17 |
| `ContentUnavailableView` | iOS 17 | `EmptyStatePlaceholder`, an icon-plus-title stack |
| `onChange(of:)` two-parameter closure | iOS 17 | `onChangeCompat(of:perform:)`, the single-parameter overload |
| `containerRelativeFrame(_:alignment:_:)` | iOS 17 | Container height measured via `ContainerHeightKey` preference |
| `AVCaptureConnection.videoRotationAngle` | iOS 17 | `videoOrientation`, mapped in `PresenceDetector.videoOrientation()` |
| `NavigationSplitView` | iOS 16 | Column-style `NavigationView`; sidebar rows are tagged `NavigationLink`s (`SettingsView.splitView`) |
| `NavigationStack` | iOS 16 | `NavigationStackCompat`, a stack-style `NavigationView` |
| `LabeledContent` | iOS 16 | `LabeledRow`, a title / spacer / content `HStack` |
| `UnevenRoundedRectangle` | iOS 16 | `UnevenRoundedRectangleCompat`, a hand-built path with circular corners |
| `scrollContentBackground(_:)` | iOS 16 | `hiddenScrollContentBackground()` keeps the opaque grouped background |
| `Color.gradient` | iOS 16 | `gradientCompat`, the flat colour |
| `UIWindowScene.effectiveGeometry` | iOS 16 | `UIWindowScene.interfaceOrientation` |
| `buttonStyle(.glass)` and Liquid Glass styling | iOS 26 | `LegacyCircleKeyStyle` in `PINEntryOverlay.swift` |

Two things follow from this. Adding a modifier from a recent SDK means gating it the same way -
the build fails otherwise, which is the intended safety net. And the visual result is deliberately
not identical across versions: older releases get the standard system appearance rather than a
hand-built imitation of the newer one.

Note that these fallback branches cannot be exercised on a modern simulator, which always takes
the newest path. Verifying them needs an iOS 15, 16 or 17 runtime, or real hardware.

---

## Adding a new feature - quick guide

**New setting:** Add a property to `AppSettings` with a `didSet` persistence call, add a `Key` case to the private enum, and add the UI to the relevant section in `SettingsView`. For `Codable` types, use `saveCodable(_:key:)` / `decodeCodable(_:forKey:)` instead of the plain `save` helper.

**New idle screen mode:** Add a case to `IdleScreenType` in `AppSettings.swift`, handle it in `IdleView.swift`'s switch, and add the corresponding UI option in `SettingsView.idleScreenDetail`.

**New detection behaviour (camera mode):** The state machine is entirely in `KioskManager`. `PresenceDetector` is responsible only for capturing a frame and returning a result - it should not need changes for most behavioural modifications.

**New presence mode:** Add a case to `PresenceMode` in `AppSettings.swift`. In `KioskManager`, add teardown/setup calls to `setPresenceMode(_:)` and `start(settings:)`. Wire any new timers through `cancelAllTimers()` so they are cleaned up on mode switch.

**New WebView behaviour:** `WebViewRepresentable` and its `Coordinator` in `KioskBrowserView.swift` are the right place for anything that touches the `WKWebView` directly.
