# Privacy Policy: DashPad

This document describes exactly what DashPad does and does not do with your data. Because the source code is publicly available, you can verify every claim here yourself.

---

## Camera

**What the camera does.**
DashPad uses the front-facing camera to detect whether someone is standing in front of the iPad. Each sample takes approximately 3 seconds: the camera activates, waits for auto-exposure to settle, captures one frame, then shuts off. The frame is analysed on-device using Apple's Vision framework (`VNDetectFaceRectanglesRequest` or `VNDetectHumanRectanglesRequest`) to determine whether a face or body is present. After analysis the frame is immediately discarded. It is never written to disk, stored in memory beyond the current cycle, or transmitted anywhere.

When the ambient light in the frame is below the configured threshold (default: luminance value 20), the app skips detection entirely and the camera is not activated for that sample. This reduces the total number of hours per day that the camera is in use.

**What the camera does not do.**
- No photos are captured or saved.
- No video is recorded.
- No frame is ever transmitted off the device.
- No third-party SDK is involved in camera processing.
- Apple's Vision framework is the only library used, and it runs entirely on-device.

---

## Settings and Configuration

All settings are stored in `UserDefaults` on the device. No settings are synced to iCloud or backed up to any cloud service.

---

## PIN

The exit PIN, when set, is stored in the iOS Keychain. It is never transmitted and never leaves the device.

---

## Network Activity

The only network requests made during normal operation originate from the `WKWebView` loading the URL you have configured. DashPad itself makes no outbound network requests. There are no telemetry pings, no version-check requests, and no analytics calls.

---

## Analytics

None. DashPad contains no crash reporting SDK, no usage tracking, and no third-party analytics framework of any kind.

---

## Third-Party SDKs

None. DashPad uses only Apple system frameworks: SwiftUI, AVFoundation, Vision, WebKit, and LocalAuthentication. There are no CocoaPods, Swift Package Manager, or Carthage dependencies.

---

## Open-Source Verification

The complete source code for DashPad is available on GitHub. Every claim in this document can be verified by reading the code directly. If you believe this document is inaccurate, please open an issue.
