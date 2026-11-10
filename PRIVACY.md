# Privacy Policy: DashPad

This document describes exactly what DashPad does and does not do with your data. Because the source code is publicly available, you can verify every claim here yourself.

---

## Camera

**What the camera does.**
DashPad uses the front-facing camera to detect whether someone is standing in front of the iPad. Each sample takes approximately 3 seconds: the camera activates, waits for auto-exposure to settle, captures one frame, then shuts off. The frame is analysed on-device using Apple's Vision framework (`VNDetectFaceRectanglesRequest` or `VNDetectHumanRectanglesRequest`) to determine whether a face or body is present. After analysis the frame is immediately discarded. It is never written to disk, stored in memory beyond the current cycle, or transmitted anywhere.

When the ambient light in the frame is below the configured threshold (default: luminance value 20), the app skips detection entirely and the camera is not activated for that sample. This reduces the total number of hours per day that the camera is in use.

**What the camera does not do.**
- The camera never captures or saves photos.
- No video is recorded.
- No frame is ever transmitted off the device.
- No third-party SDK is involved in camera processing.
- Apple's Vision framework is the only library used, and it runs entirely on-device.

---

## Settings and Configuration

All settings are stored in `UserDefaults` on the device. DashPad does not sync them to iCloud or send them anywhere. Like most app data, they are included in the iPad's own iCloud or computer backup when backups are turned on. Photos are the exception: they are excluded from backups (see Photos).

---

## Photos

If you choose the Photos idle screen, you pick photos with the system photo picker. The picker runs outside DashPad and hands over only the photos you select, so DashPad does not ask for access to your photo library and cannot see the rest of it. Each selected photo is copied into DashPad's own storage on the iPad, reduced to screen size and re-encoded; the original's metadata, such as location, is not copied. DashPad's copies are excluded from iCloud and computer backups. They are never uploaded or transmitted. Removing a photo in Settings deletes DashPad's copy; the original in your library is untouched.

---

## PIN

The exit PIN, when set, is stored in the iOS Keychain. It is never transmitted and never leaves the device.

---

## Network Activity

The only network requests made during normal operation originate from the `WKWebView` loading the URL you have configured. DashPad itself makes no outbound network requests. There are no telemetry pings, no version-check requests, and no analytics calls.

---

## Home Assistant Link

The Home Assistant link is off by default. While it is off, DashPad accepts no network connections and announces nothing on your network.

If you turn it on in Settings → Home Assistant:

- DashPad announces itself on your local network (Bonjour, `_esphomelib._tcp`) with the device name you chose, a made-up device identifier and its version, so Home Assistant can find it.
- DashPad accepts connections on TCP port 6053. Every connection is encrypted and must prove it holds the encryption key shown in Settings; anything else is refused. The key is stored in the iOS Keychain.
- To a connected Home Assistant, DashPad reports: whether the camera currently sees someone, whether the screen is showing the dashboard, the idle screen or the night screen, the average brightness of the last camera frame (a single number), the battery level and whether the iPad is charging, the device name, the iPad model name and the DashPad version.
- Home Assistant can change what the screen shows and open a web page in the dashboard, limited to the domains you allow in Settings.

No camera image, photo, PIN or other setting is ever sent. DashPad still makes no outbound connections: Home Assistant connects to the iPad, never the other way round, and DashPad holds no Home Assistant password or token. Nothing is sent to the developer or to any third party. What Home Assistant does with the information it receives is governed by your Home Assistant installation.

---

## Analytics

None. DashPad contains no crash reporting SDK, no usage tracking, and no third-party analytics framework of any kind.

---

## Third-Party SDKs

None. DashPad uses only Apple system frameworks: SwiftUI, AVFoundation, Vision, WebKit, LocalAuthentication, PhotosUI, ImageIO, Core Image, Network, CryptoKit, and TipKit. TipKit shows an in-app tip and remembers on the device whether it has been dismissed; nothing is transmitted. There are no CocoaPods, Swift Package Manager, or Carthage dependencies.

---

## Open-Source Verification

The complete source code for DashPad is available on GitHub. Every claim in this document can be verified by reading the code directly. If you believe this document is inaccurate, please open an issue.
