# Changelog

All notable changes to DashPad are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
