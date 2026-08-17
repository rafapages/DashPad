# Changelog

All notable changes to DashPad are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- Re-running Settings → Setup assistant no longer discards the configured dashboard URL. Since the
  URL step was reworked to require an explicit choice, it cleared the field on appear and could not
  be passed without picking a card — so any re-run replaced a custom `homeURL` with the Home
  Assistant default or an empty field. A re-run now starts from the existing configuration.
- Onboarding's idle screen step offered Custom URL without ever asking for the URL, saving the mode
  with an empty `idleCustomURL`: `IdleView` fell back to the clock while Settings reported Custom
  URL. The step now collects and validates the URL before committing that choice.
- URL validation required an `http://` or `https://` prefix but not a host, so `"http://"` was
  accepted and stored. Both URL fields now require a parseable URL with a host.
- Settings → Setup assistant can be left with a Close button. Previously the only way out of a
  re-run was to walk all six steps, re-answering every question.
- The presence step no longer does nothing when camera access is already granted but Presence Mode
  is not Automatic — it now says so, and where to change it, rather than silently advancing.
- Onboarding steps can no longer be skipped by a double-tap on a step button, and `advance()` is
  clamped to the last step instead of running past it into a stepless state.
- Onboarding dismisses its own sheet before running its completion handler, so finishing a re-run
  no longer tears down the presenting settings sheet mid-dismissal.
- The welcome card's animated gradient kept running after the welcome step left the screen, and
  started an additional loop every time the step reappeared, so the loops accumulated and competed
  for the same state. The keyframe cycle is now driven by `task`, which is bound to the view's
  lifetime. The gradient's rendering is untouched — keyframes, colours, radii, blur and
  colour-dodge blend all draw exactly as before.
- `measureContainerHeight()` no longer lays out a GeometryReader and publishes a preference on
  iOS 17+, where `containerRelativeFrame` measures its own container and nothing reads the value.
- The PIN entry screen drew six dots for a PIN that setup always creates with four. The six-slot
  row dated from an earlier design where the PIN was a free-text field accepting 4–6 digits; when
  that was replaced by the fixed-length setup keypad, the entry screen was never updated. Both
  screens now size themselves from `AppSettings.pinLength`, and the entry screen accepts a longer
  PIN saved by an older build rather than becoming impossible to type.
- `KioskManager.validatePIN(_:)` returned `true` for any input when no PIN was stored. Unreachable
  in practice — the secret gesture opens Settings directly when no PIN is set — but it no longer
  depends on that guard being correct elsewhere.
- Onboarding could not get past the PIN Lock step when the PIN entered matched the one already
  stored — the step advanced by comparing the PIN before and after, and re-entering the same PIN
  changes no value. `PINSetupView` now reports success through a callback instead.
- A PIN left in the Keychain by a previous install (Keychain items outlive app deletion) is now
  cleared on a fresh install, so a reinstalled DashPad no longer starts out locked by a PIN the
  user never set in this install.
- Choosing a presence mode during onboarding only wrote it to settings and never told
  `KioskManager`, so declining the camera left the camera pipeline running: the dashboard kept
  dropping to the idle screen despite being in Always Active mode.
- The camera pipeline no longer starts while onboarding is on screen. It previously began at
  launch, raising the system camera dialog behind the onboarding sheet roughly 30 seconds in and
  dimming the screen to the idle brightness mid-setup.
- The presence step no longer looks inert when the camera decision has already been made.
  `requestAccess` only shows the system dialog while the status is `.notDetermined`; the step now
  explains a denied or restricted state instead of silently advancing, and distinguishes access
  denied for DashPad from camera use blocked device-wide by Screen Time or a management profile.
- Re-running the setup assistant no longer overwrites a deliberately chosen presence mode.
  Automatic is still swapped for Always Active when the camera is unavailable, since it cannot
  work, but Schedule mode is left alone.
- The "Camera access is off" warning in Settings → Presence was only rendered in Automatic mode,
  making it unreachable for users who had just been moved to Always Active by declining the
  camera — the exact case it exists for. It now shows in any presence mode.

### Changed
- Lowered the deployment target from iOS/iPadOS 18.6 to 16.0, extending support back to the iPad
  5th generation (2017) and the original iPad Pro (2015). See
  [Supported iPads](README.md#supported-ipads) for the caveats on the oldest devices.
- Migrated the state layer from the Observation framework (`@Observable`, `@Bindable`,
  `@Environment(Type.self)`) to `ObservableObject` / `@Published` / `@EnvironmentObject`, which is
  what the lower target requires. `KioskManager.lastLuminance` and `manualWakeUntil` are
  intentionally left unpublished so per-sample camera updates no longer invalidate the view tree.
- Collected all availability gating in `Support/AvailabilityCompat.swift`. Behaviour on iOS 26 is
  unchanged; older releases fall back to the standard system appearance.

## [1.0.0] - 2026-06-29

First public, source-available release.

### Added
- Full-screen `WKWebView` kiosk browser with auto-reload on connection loss and a configurable domain allowlist.
- Three presence modes: Automatic (Camera), Schedule, and Always Active.
  - **Automatic (Camera).** On-device presence detection using Apple's Vision framework. Single-frame capture (about 3 seconds of camera activity per sample), gated by ambient light, with separate day and night sample rates. Body or face detection. Frames are processed in memory and discarded.
  - **Schedule.** Time-based Active/Idle transitions with no camera use. One or more Active windows per day, shared or per day of the week, including midnight-spanning windows (e.g. 22:00 to 07:00). A tap on the idle screen wakes the dashboard for a configurable Manual Wake Timeout (default 120 s), with each tap resetting the timer.
  - **Always Active.** Dashboard stays on at all times.
- Idle screen with Clock (digital or analogue), Blank, and Custom URL modes. Independent active and idle brightness.
- Optional PIN lock (off by default) gating the settings panel, with Face ID or device passcode fallback.
- Settings panel accessed via a triple-tap secret gesture.
- First-run onboarding flow.
