# Home Assistant link

**Status:** Implemented, off by default
**Source files:** `HomeAssistant/ESPHomeServer.swift`, `HomeAssistant/NoiseHandshake.swift`, `HomeAssistant/ProtoWire.swift`, `HomeAssistant/HomeAssistantLink.swift`, `KioskManager.swift`

The Home Assistant link makes the iPad appear in Home Assistant as a device with its own entities: a presence sensor, the state of the screen, a mode selector, battery, and a couple of controls. Automations can read those and can wake the dashboard, send it idle, show the night screen or open a page.

This document explains how it works, for anyone who wants to use it, extend it, or build something similar. It assumes no knowledge of ESPHome.

---

## The short version

- DashPad pretends to be an **ESPHome device**. Home Assistant already knows how to talk to those, so nothing has to be installed in Home Assistant: no add-on, no HACS integration, no YAML.
- The iPad **listens**; Home Assistant **connects**. DashPad never opens a connection to Home Assistant and holds no Home Assistant login or token.
- The connection is **encrypted** with a key shown in Settings. Unencrypted clients are refused.
- It only works while DashPad is on screen, which for a kiosk is always.

---

## ESPHome in five minutes

[ESPHome](https://esphome.io) is firmware for small Wi-Fi microcontrollers (ESP32 and similar): the boards behind most DIY temperature sensors, smart plugs and LED strips. It is part of the Home Assistant project, and Home Assistant ships with an **ESPHome integration** built in.

An ESPHome device and Home Assistant talk over the **ESPHome native API**:

1. **Discovery.** The device announces itself on the local network over mDNS (Bonjour) as a `_esphomelib._tcp` service. Home Assistant notices and shows it under *Discovered*.
2. **Connection.** Home Assistant opens a TCP connection to the device on port 6053 and keeps it open.
3. **Description.** Home Assistant asks "who are you?" and "what entities do you have?". The device answers with its name and a list such as "a binary sensor called Presence, a select called Mode with these four options".
4. **State.** Home Assistant subscribes, and from then on the device pushes a message every time a value changes.
5. **Commands.** When an automation or a person changes something, Home Assistant sends a command message, such as "set select Mode to Night".

The device describes itself, so Home Assistant needs no knowledge of what kind of device it is. That is why an iPad can take part: DashPad implements the device side of this protocol, and Home Assistant treats it like any other ESPHome device. It is listed under the ESPHome integration, with DashPad as the manufacturer.

DashPad is not ESPHome firmware and is not affiliated with the ESPHome project. It implements the subset of the protocol it needs. The ESPHome dashboard, firmware updates and logs do not apply to it.

---

## Setting it up

1. In DashPad, open **Settings → Home Assistant** and turn on **Home Assistant Link**. iPadOS may ask for Local Network access; allow it.
2. Optionally change **Device Name** (for example "Kitchen iPad").
3. In Home Assistant, open **Settings → Devices & services**. The iPad should appear under *Discovered*. If it doesn't, choose **Add integration → ESPHome** and enter the address and port shown in DashPad.
4. When Home Assistant asks for the **encryption key**, enter the one shown in DashPad's settings.

### Entities

| Entity | Type | Values |
| --- | --- | --- |
| Presence | Binary sensor (occupancy) | On while the camera sees someone. Unknown outside Camera mode, and while the camera is off for the night screen. |
| Display | Text sensor | `dashboard`, `idle` or `night`: what is on screen right now. |
| Mode | Select | `Auto`, `Dashboard`, `Idle`, `Night`: what Home Assistant has asked for. |
| Room Brightness | Sensor | Average brightness of the last camera frame, 0 to 255. Not lux. Camera mode only. |
| Battery | Sensor (diagnostic) | Percent. |
| Charging | Binary sensor (diagnostic) | On while charging or full. |
| Reload Dashboard | Button | Returns to the home URL and reloads it. |

One action is also registered, `show_url`, with a `url` (text) and a `duration` (seconds). Home Assistant lists it as `esphome.<device name>_show_url`; Developer tools → Actions shows the exact name.

### Mode

- **Auto** leaves everything to DashPad: the presence mode (camera, schedule or always active) and the night hours. This is the default and what every launch starts in.
- **Dashboard** keeps the dashboard on screen.
- **Idle** shows the idle screen. During the night hours that is the night screen.
- **Night** shows the night screen, whatever the time.

A tap on the screen always wakes the dashboard, for the Manual Wake Timeout (Settings → Presence, Schedule mode) and for as long as the camera still sees someone. Then the requested mode applies again.

If Home Assistant stays disconnected for five minutes, the mode returns to Auto, so a Home Assistant that is down cannot leave the screen stuck. Automations that hold a mode should set it again when the device comes back.

### Example automations

Show the night screen when the bedroom lights go off, and hand control back in the morning:

```yaml
- alias: Kitchen iPad night screen
  triggers:
    - trigger: state
      entity_id: light.bedroom
      to: "off"
  actions:
    - action: select.select_option
      target:
        entity_id: select.kitchen_ipad_mode
      data:
        option: Night
```

Show the doorbell camera for 30 seconds, then return to the dashboard and whatever mode was in force:

```yaml
- alias: Doorbell on the kitchen iPad
  triggers:
    - trigger: state
      entity_id: binary_sensor.doorbell
      to: "on"
  actions:
    - action: esphome.kitchen_ipad_3fa2c1_show_url
      data:
        url: http://homeassistant.local:8123/doorbell/camera?kiosk
        duration: 30
```

`show_url` respects Settings → Dashboard → Allowed Domains: a URL the dashboard itself could not navigate to is ignored. A `duration` of 0 keeps the page up until the mode changes or Reload Dashboard is pressed.

---

## How it is built

```
Home Assistant                              iPad (DashPad)
┌──────────────────┐   mDNS _esphomelib._tcp   ┌───────────────────────────────┐
│ ESPHome          │ ◄──────────────────────── │ ESPHomeServer                 │
│ integration      │                           │  NWListener, port 6053        │
│ (aioesphomeapi)  │ ── TCP, Noise encrypted ─►│  ESPHomeConnection (framing)  │
└──────────────────┘                           │  NoiseHandshake / NoiseCipher │
                                               │  ProtoWriter / ProtoReader    │
                                               └──────────────┬────────────────┘
                                                 states ▲     │ commands
                                               ┌────────┴─────▼────────────────┐
                                               │ HomeAssistantLink             │
                                               └────────┬─────▲────────────────┘
                                                        ▼     │
                                               KioskManager, WebViewController
```

There are no third-party dependencies. `Network.framework` provides the listener and Bonjour, CryptoKit provides the cryptography, and the protobuf encoding is hand-written.

### `ESPHomeServer`: the generic part

`ESPHomeServer` knows nothing about DashPad. It is constructed with:

- an `ESPHomeDevice` (name, friendly name, MAC address, model, version),
- a 32-byte key,
- a list of `ESPHomeEntity` values (binary sensor, sensor, text sensor, select, button),
- a list of `ESPHomeAction` values (named actions with typed arguments).

After `start()`, the owner calls `setState(_:for:)` whenever a value changes, and receives `ESPHomeCommand` values through `onCommand`. `setState` ignores a value equal to the last one, so callers can report everything on every change without flooding Home Assistant. A `nil` state is sent as "unknown".

Everything runs on the main queue. Traffic is a few small messages a minute, and it keeps the server on the same thread as the app state it reports.

### Discovery

The listener registers a Bonjour service of type `_esphomelib._tcp`, named after the device, with these TXT records:

| Key | Value | Why |
| --- | --- | --- |
| `mac` | 12 hex digits | Required. Home Assistant uses it as the device's unique ID. |
| `friendly_name` | The Device Name setting | Shown in the discovery card. |
| `api_encryption` | `Noise_NNpsk0_25519_ChaChaPoly_SHA256` | Tells Home Assistant to ask for a key. |
| `version`, `project_name`, `project_version` | | Informational. |

iOS does not let apps read the real MAC address, so DashPad makes one up on first use and keeps it (`AppSettings.homeAssistantMACAddress`). Its first byte marks it as locally administered, so it cannot collide with real hardware.

The device name is derived from the Device Name setting: "Kitchen iPad" becomes `kitchen-ipad-3fa2c1`. ESPHome names allow only lowercase letters, digits and hyphens, and the suffix (the end of the MAC address) keeps two iPads with the same name apart.

Bonjour needs two Info.plist entries: `NSBonjourServices` listing `_esphomelib._tcp` (in `DashPad-Info.plist`) and `NSLocalNetworkUsageDescription`.

### Framing and encryption

Every frame on the wire is:

```
0x01 | length (16-bit big-endian) | body
```

The first frames carry the handshake:

| Direction | Body | Meaning |
| --- | --- | --- |
| Client → device | (empty) | Client hello. |
| Client → device | `0x00` + Noise message 1 | Client's ephemeral public key, proof of the pre-shared key. |
| Device → client | `0x01` + name + `\0` + MAC + `\0` | Server hello: chosen protocol, and who the device is. |
| Device → client | `0x00` + Noise message 2 | Device's ephemeral public key. |

After the handshake, each frame's body is one encrypted message. Decrypted, it is:

```
message type (16-bit big-endian) | payload length (16-bit big-endian) | protobuf payload
```

The encryption is the [Noise protocol](https://noiseprotocol.org/noise.html) `Noise_NNpsk0_25519_ChaChaPoly_SHA256`, with the prologue `NoiseAPIInit\0\0`:

- **NN**: neither side has a long-term key pair.
- **psk0**: both sides mix a 32-byte pre-shared key in at the start. This is the "encryption key" in Settings. A client without it cannot produce a valid first message.
- **25519**: fresh X25519 key pairs per connection, so recorded traffic cannot be decrypted later even if the key leaks.
- **ChaChaPoly / SHA256**: ChaCha20-Poly1305 for encryption, SHA-256 and HMAC-SHA256 for key derivation.

`NoiseHandshake` implements the device (responder) side in about 150 lines on CryptoKit. `NoiseCipher` is one direction of the established session: ChaCha20-Poly1305 with a nonce of four zero bytes followed by a 64-bit little-endian counter.

Two failure replies matter, because Home Assistant recognises them:

- A client that starts with `0x00` is speaking the unencrypted protocol. The device answers with a frame whose body is `0x01` + `Bad indicator byte` and hangs up. The `0x01` at the start of that reply is how the client learns encryption is required, and Home Assistant then asks for the key.
- A first message that fails to authenticate means the wrong key. The device answers `0x01` + `Handshake MAC failure`, which Home Assistant reports as an invalid encryption key.

DashPad does not support the unencrypted protocol at all.

### Messages

Payloads are Protocol Buffers, defined in ESPHome's [`api.proto`](https://github.com/esphome/esphome/blob/dev/esphome/components/api/api.proto). Each message has a number (`option (id)` in that file), which is the message type in the frame. `ProtoWire.swift` implements just the encodings those messages use: varints, length-delimited fields and 32-bit fixed fields.

A normal session:

| # | Direction | Message | Purpose |
| --- | --- | --- | --- |
| 1 / 2 | → / ← | HelloRequest / HelloResponse | API version (DashPad reports 1.10) and device name. |
| 9 / 10 | → / ← | DeviceInfoRequest / DeviceInfoResponse | Name, MAC, model, versions. |
| 11 | → | ListEntitiesRequest | |
| 12, 16, 18, 52, 61 | ← | ListEntities…Response | One per entity: binary sensor, sensor, text sensor, select, button. |
| 41 | ← | ListEntitiesServicesResponse | One per action, with its arguments. |
| 19 | ← | ListEntitiesDoneResponse | End of the list. |
| 20 | → | SubscribeStatesRequest | Device sends every current state, then changes. |
| 21, 25, 27, 53 | ← | …StateResponse | A value changed. |
| 54 | → | SelectCommandRequest | Set a select. |
| 62 | → | ButtonCommandRequest | Press a button. |
| 42 | → | ExecuteServiceRequest | Run an action. |
| 7 / 8 | ↔ | PingRequest / PingResponse | Keep-alive. Home Assistant pings every 20 seconds. |
| 5 / 6 | ↔ | DisconnectRequest / DisconnectResponse | Orderly goodbye. |

Each entity has a 32-bit **key**, which state and command messages use in place of its name. DashPad derives it from the entity's ID with FNV-1, the hash ESPHome uses.

Messages the server does not implement (log subscription, time, Bluetooth proxy and so on) are ignored, as a real device without those features would.

### `HomeAssistantLink`: the DashPad part

`HomeAssistantLink` owns the server and maps it to the app:

- **Lifecycle.** It starts after onboarding (so the Local Network prompt cannot appear behind the setup sheet) and follows `AppSettings.homeAssistantLinkEnabled`. Changing the device name or the key restarts the server.
- **States.** It observes `KioskManager.objectWillChange`, and sweeps every 5 seconds for values that don't publish changes (camera luminance, battery). Each pass reports every entity; the server drops what hasn't changed.
- **Commands.** The Mode select calls `KioskManager.setRequestedMode(_:)`. Reload Dashboard calls `WebViewController.goHome`. `show_url` calls `KioskManager.holdDashboard(for:onEnd:)` and `WebViewController.show(_:)`, after checking the URL against the allowlist.
- **Safety net.** Five minutes without a connected client, or turning the link off, sets the mode back to Auto.

### How `KioskManager` resolves what to show

Home Assistant never drives the presence state machine. The presence modes still decide what they would show and record it in `localDisplayState`. `resolveDisplay()` then picks the winner, in this order:

1. A **dashboard hold** (a tap on a requested idle screen, or `show_url`): dashboard.
2. The **requested mode**: Dashboard, Idle or Night.
3. In Auto, the **presence mode's** own decision.

Because the camera pipeline keeps running underneath, the Presence sensor stays truthful while Home Assistant forces a mode, and returning to Auto picks up exactly where the presence mode is.

### The key

The key is 32 random bytes, base64-encoded, stored in the Keychain and created on first launch. Like the PIN, it is deleted on a fresh install. **New Key** in Settings replaces it; Home Assistant then fails to connect until the new key is entered there.

---

## Extending it

### Adding an entity

1. Add an `ESPHomeEntity` to `HomeAssistantLink.entities`, with a new ID.
2. Report its value in `publishStates()` with `server.setState(_:for:)`.
3. For a select or button, handle its `ESPHomeCommand` in `handle(_:)`.

Home Assistant picks up new entities the next time it connects.

### Adding an entity type

`ESPHomeServer` supports binary sensor, sensor, text sensor, select and button. To add another (number, switch, light), add a case to `ESPHomeEntity.Kind`, then the three messages from `api.proto`: its `ListEntities…Response`, its `…StateResponse` and, if it can be controlled, its `…CommandRequest`. The field numbers differ per type, so copy them from `api.proto`.

### Testing without Home Assistant

[`aioesphomeapi`](https://github.com/esphome/aioesphomeapi) is the Python library Home Assistant's integration is built on, so a script using it exercises the same code path. The simulator shares the Mac's network, so a simulator build is reachable on `127.0.0.1:6053`.

In Debug builds, the environment variable `DASHPAD_HA_KEY` overrides the Keychain key, so a script can know it:

```sh
SIMCTL_CHILD_DASHPAD_HA_KEY="$KEY" xcrun simctl launch booted com.rafapages.dashpad
```

```python
import asyncio
from aioesphomeapi import APIClient

async def main():
    client = APIClient("127.0.0.1", 6053, None, noise_psk=KEY)
    await client.connect(login=True)
    print(await client.device_info())
    entities, actions = await client.list_entities_services()
    client.subscribe_states(print)
    mode = next(e for e in entities if e.object_id == "mode")
    client.select_command(mode.key, "Night")
    await asyncio.sleep(5)
    await client.disconnect()

asyncio.run(main())
```

---

## Limits

- **Foreground only.** iOS suspends the listener when DashPad is not on screen. The server reopens it when the app becomes active again.
- **Presence is a camera, not a radar.** It turns on within about 8 seconds, clears after the recheck interval plus the idle timeout (about 90 seconds at the defaults), and sees nothing in the dark. With the night screen's "Wake When Someone Walks Up" off, the camera is off while the night screen shows and Presence reads unknown.
- **The mode is not remembered.** Every launch starts in Auto.
- **The address can change.** Home Assistant stores the IP address it found and updates it from Bonjour announcements. On a network where mDNS does not reach Home Assistant (some Docker and VLAN setups), give the iPad a fixed address.
- **The protocol can move.** This follows ESPHome's native API as of ESPHome 2026.1. It is stable and versioned, but it is defined by the ESPHome project, not by DashPad.
