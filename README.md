# DashPad

**A native iOS/iPadOS app that turns an iPad into a dedicated, always-on Home Assistant dashboard.**

License: PolyForm NC
Platform: iOS/iPadOS 18+
Swift

> Source-available, non-commercial. Free to view, build, and use personally. Building or shipping a commercial product from this code requires a separate license. See [License](#license).

---

<p align="center">
  <video src="https://raw.githubusercontent.com/rafapages/rafapages.github.io/main/dashpad/uploads/videos/dashpad.mp4" controls muted playsinline width="80%"></video>
</p>

---



## What it does

Mount an iPad on your wall. Open DashPad. Walk away.

DashPad loads your Home Assistant dashboard full-screen, with no browser chrome, no address bar, nothing but your dashboard. When you walk up, the screen wakes and shows the dashboard. When you walk away, it dims to a clock or goes blank. When you come back, it wakes again. All of this is driven by the front camera running Apple's Vision framework entirely on-device. No data leaves the iPad.

It is a general-purpose iPad kiosk browser. Home Assistant is the hero use case, not a hard dependency: point it at any URL and it works the same way.

---



## Why not just use the HA app with Guided Access?

The native HA app works fine as a browser, but it gives you no presence detection, no idle screen, and the Guided Access setup is manual and clunky. Every time you want to change something you are triple-clicking the side button and entering a system-level PIN.

The commercial iOS kiosk apps are priced and designed for retail and museum deployments. They are overkill for a single home iPad, and none of them combine camera-based presence detection with a privacy-first, fully local architecture.

---



## Features

**Full-screen kiosk browser.** Loads your dashboard URL in a `WKWebView` that fills the entire display. Auto-reloads on connection loss. Scroll bounce, text selection, and context menus are all disabled. Navigation outside a configurable domain allowlist is blocked.

**Flexible presence control, three modes.** Choose how the app decides when to show the dashboard:

- **Automatic (Camera).** Privacy-first, camera-based detection. At each sample interval (default: every 5 s) DashPad starts a fresh camera session, waits roughly 3 seconds for auto-exposure to settle, captures a single frame, then immediately tears the session down. That frame is analysed on-device by Apple's Vision framework and discarded. Nothing is written to disk or transmitted. When the room is dark the sample is skipped and rescheduled at a slower night rate (default: every 60 s), so the camera is barely active overnight.
- **Schedule.** No camera used. Define one or more Active windows by time of day; everything outside a window goes idle automatically. Windows can be the same every day or configured per day of the week. Midnight-spanning windows (e.g. 22:00 to 07:00) are supported. While idle, a single tap anywhere on the idle screen wakes the dashboard for a configurable duration, with each subsequent tap resetting the timer.
- **Always Active.** The dashboard stays on at all times. No detection of any kind is performed.

**Idle screen.** Three modes: a digital or analogue clock, a pure black screen, or a custom URL (useful for a dedicated screensaver dashboard or a photo frame). Active and idle brightness are independently configurable.

**Optional PIN lock.** A PIN can be set to gate access to settings. It is off by default. Face ID or your device passcode can unlock it if you forget the PIN.

**Settings panel.** Accessed via a secret gesture (triple-tap the bottom-right corner). No visible settings button means no clutter on the dashboard.

---



## Roadmap

- **Custom CSS/JS injection into the WebView** is planned but not yet shipped. It was removed pending proper testing of its security and stability implications. Once re-enabled it will let you hide the Home Assistant sidebar, increase font sizes for readability at a distance, or suppress UI elements that do not make sense on a permanently mounted display, all without modifying your Home Assistant installation.

---



## Requirements

- Xcode 16 or later
- iOS / iPadOS 18.0 deployment target (developed and tested on iOS 26)
- An Apple ID for code signing
- A **physical iPad**. The simulator has no camera and cannot run the presence detection pipeline.

---



## Getting Started



### Build and run

```bash
git clone https://github.com/rafapages/DashPad.git
```

1. Open `DashPad.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your own development team. The project ships with `DEVELOPMENT_TEAM` left blank, so you must set this before the first build.
3. Set a unique bundle identifier. The default `com.example.dashpad` is a placeholder and will collide; change it to something of your own (e.g. `com.yourname.dashpad`).
4. Build and run on a physical iPad (`⌘R`). A camera and Guided Access need real hardware.

On first launch, an onboarding flow walks you through setup: setting your Home URL, granting camera permission, choosing an idle screen, and optionally setting a PIN.

### First-run checklist

- Set your **Home URL** (e.g. `http://homeassistant.local:8123/lovelace/main`)
- Optionally set an **Exit PIN**. Without one, anyone who triple-taps the corner can open settings.
- Grant **camera permission** when iOS prompts. Presence detection will not work without it.
- Adjust **Day Sample Rate** and **Idle Timeout** to taste; the defaults are conservative.

---



## Configuration

Open the settings panel by **triple-tapping the bottom-right corner**. If an exit PIN is set, you will be prompted for it first.

### Dashboard


| Setting         | Default                           | Description                                                                                                                      |
| --------------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Home URL        | `http://homeassistant.local:8123` | The dashboard URL loaded on launch and after connection failures.                                                                |
| Allowed domains | *(empty, allow all)*              | Comma-separated list of domains the WebView may navigate to. Useful if your dashboard links to external pages you want to block. |
| Favourites      | *(empty)*                         | Saved URL list. Swipe right on any entry to set it as the Home URL; swipe left to delete.                                        |




### Presence

**Presence Mode** picker, the first control in the Presence section:


| Mode               | Behaviour                                                                            |
| ------------------ | ------------------------------------------------------------------------------------ |
| Automatic (Camera) | Camera-based detection pipeline. See camera settings below.                          |
| Schedule           | Time-based Active/Idle transitions. Camera is not used. See schedule settings below. |
| Always Active      | Dashboard stays on at all times. No additional controls.                             |




#### Automatic (Camera) settings


| Setting           | Default | Description                                                                                                                                                                                   |
| ----------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Detection mode    | Body    | `Body` uses `VNDetectHumanRectanglesRequest`, which works for side profiles and people facing away. `Face` uses `VNDetectFaceRectanglesRequest`, which is faster but requires a visible face. |
| Day sample rate   | 5 s     | Seconds between camera samples when the room is lit. Lower is more responsive; higher saves battery.                                                                                          |
| Night sample rate | 60 s    | Seconds between samples when the frame luminance is below the dark threshold.                                                                                                                 |
| Recheck interval  | 30 s    | How long after detecting presence before the camera checks again to confirm someone is still there.                                                                                           |
| Idle timeout      | 60 s    | Seconds of no detected presence before the idle screen appears.                                                                                                                               |
| Dark threshold    | 20      | Average frame luminance (0 to 255) below which the room is considered dark. Dark frames skip the detector entirely.                                                                           |




#### Schedule settings


| Setting                 | Default  | Description                                                                                                                                                                                                                                                            |
| ----------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Manual Wake Timeout     | 120 s    | How long the dashboard stays visible after tapping the idle screen. Range: 30 to 600 s. Each tap resets the timer.                                                                                                                                                     |
| Same Schedule Every Day | On       | When on, a single set of Active windows applies to every day. When off, each day of the week has its own independent list.                                                                                                                                             |
| Active Windows          | *(none)* | One or more time ranges during which the dashboard is shown. Tap **+** to add a window; swipe left on a row to delete it. A window whose end time is earlier than its start time spans midnight (e.g. 22:00 to 07:00). Overlapping windows are rejected by the editor. |




### Idle screen

Three mutually exclusive modes:


| Mode       | Description                                                                |
| ---------- | -------------------------------------------------------------------------- |
| Clock      | Full-screen clock. Choose Digital or Analog style.                         |
| Blank      | Pure black screen. Pair with a low idle brightness to minimise power draw. |
| Custom URL | Loads a URL in the WebView, useful for a dedicated screensaver dashboard.  |




### Brightness


| Setting           | Default | Description                                    |
| ----------------- | ------- | ---------------------------------------------- |
| Active brightness | 80%     | Screen brightness when the dashboard is shown. |
| Idle brightness   | 15%     | Screen brightness on the idle screen.          |


---



## Architecture

DashPad is organised into a small number of focused groups. Here is where to look depending on what you want to change.

```
DashPad/
├── DashPadApp.swift      Entry point; owns AppSettings and KioskManager
├── AppSettings.swift     Single source of truth for all user configuration
├── KioskManager.swift    Central coordinator; presence state machine; display transitions
├── ContentView.swift     Root view; switches between KioskBrowserView and IdleView
├── Kiosk/                WKWebView wrapper and navigation policy
├── Presence/             Camera capture, Vision requests, presence debug overlay
├── Idle/                 Idle screen views (clock, blank, custom URL)
├── Onboarding/           First-run onboarding flow and animated backgrounds
└── Settings/             SwiftUI settings panel, PIN entry and setup
```

`AppSettings` (`AppSettings.swift`) is the single source of truth for all user configuration. It is an `@Observable` class injected into the SwiftUI environment at the root and read directly by any view or manager that needs it. Settings are persisted to `UserDefaults` via `didSet` observers. The exit PIN is the only value stored in Keychain.

`KioskManager` (`KioskManager.swift`) is the central coordinator. It drives the display state machine (`active` / `idle`), manages all three presence modes (camera pipeline, schedule timer, or always-active), handles the secret gesture and PIN flow, and manages screen brightness transitions. Views observe it via the SwiftUI environment.

`PresenceDetector` (`Presence/PresenceDetector.swift`) owns everything camera-related. `KioskManager` calls it with `captureOnce()` whenever the state machine wants a sample. It starts a fresh `AVCaptureSession`, waits for auto-exposure to settle, grabs one frame, runs the Vision request, tears the session down, and calls back with a result. It knows nothing about the state machine; it just captures and reports.

`ContentView` (`ContentView.swift`) is a thin switcher. It reads `KioskManager.displayState` and renders either `KioskBrowserView` (active) or `IdleView` (idle), plus the PIN overlay when needed.

For a full architectural narrative, see [docs/architecture.md](docs/architecture.md). For a deeper walkthrough of the presence pipeline specifically, see [docs/presence-pipeline.md](docs/presence-pipeline.md).

---



## Privacy

DashPad is built around a simple principle: the iPad is yours, and what happens on it stays on it.

- **No analytics.** No crash reporters, no usage tracking, no third-party SDKs of any kind.
- **The camera runs in short bursts, not continuously.** Each sample starts a fresh session, waits about 3 seconds for auto-exposure to settle, captures one frame, then tears the session down. That frame is processed in memory by Apple's Vision framework and immediately discarded. Nothing is written to disk or transmitted.
- **The camera is off when the room is dark.** If the captured frame's luminance falls below the configured threshold, the detector does not run and the next sample is scheduled at the slower night rate.
- **No outbound network requests** originate from the app itself. All network activity is the WebView loading your URL.
- **Settings are stored on-device only** in `UserDefaults`. No iCloud sync, no cloud backup.
- **The exit PIN is stored in the iOS Keychain** and never transmitted.

Because the source is available, you can verify every one of these claims in the code directly. See [PRIVACY.md](PRIVACY.md) for the full statement.

---



## Try it

**TestFlight beta — available now.** Want to run a signed build today without compiling it yourself? Join the public beta. <!-- TODO: add TestFlight link --> *(invite link coming shortly)*

**App Store — coming soon.** A signed binary will be available on the App Store as a one-time purchase, for those who want the convenience of an installed, signed build. The link will be added on launch. It is built from this same codebase.

---



## License

DashPad is **source-available, not open source**: free to view, build, and use for personal and other non-commercial purposes under the [PolyForm Noncommercial License 1.0.0](LICENSE).

Building, distributing, or selling a product based on this code requires a separate commercial license. These are available at affordable rates; see [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md) or contact **[dashpad@rafapages.com](mailto:dashpad@rafapages.com)**.

---



## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).