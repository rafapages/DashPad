// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// HomeAssistantLink.swift - the bridge between DashPad and the ESPHome server. It decides which
// entities the iPad exposes, keeps their values in step with KioskManager, and turns Home
// Assistant's commands into calls on KioskManager and WebViewController. Off unless
// AppSettings.homeAssistantLinkEnabled is on. See docs/home-assistant-link.md.

import Combine
import SwiftUI
import UIKit

final class HomeAssistantLink: ObservableObject {
    /// What Settings shows: stopped, starting, listening (with the number of clients), or failed.
    @Published private(set) var status: ESPHomeServer.Status = .stopped

    private var settings: AppSettings?
    private var kioskManager: KioskManager?
    private var webController: WebViewController?

    private var server: ESPHomeServer?
    private var runningConfiguration: Configuration?
    private var observers: Set<AnyCancellable> = []
    private var stateTimer: Timer?
    private var restartTimer: Timer?
    private var disconnectTimer: Timer?

    /// How long Home Assistant may stay disconnected before a mode it requested is dropped, so
    /// a restarted or broken Home Assistant can't leave the screen stuck.
    private static let disconnectGrace: TimeInterval = 300

    // MARK: - Entities

    private enum EntityID {
        static let presence = "presence"
        static let display = "display"
        static let mode = "mode"
        static let roomBrightness = "room_brightness"
        static let battery = "battery"
        static let charging = "charging"
        static let reload = "reload_dashboard"
    }

    private static let showURLAction = "show_url"

    private static let entities: [ESPHomeEntity] = [
        ESPHomeEntity(id: EntityID.presence, name: "Presence",
                      kind: .binarySensor(deviceClass: "occupancy")),
        ESPHomeEntity(id: EntityID.display, name: "Display", icon: "mdi:monitor",
                      kind: .textSensor),
        ESPHomeEntity(id: EntityID.mode, name: "Mode", icon: "mdi:monitor-dashboard",
                      kind: .select(options: RequestedMode.allCases.map(\.rawValue))),
        ESPHomeEntity(id: EntityID.roomBrightness, name: "Room Brightness", icon: "mdi:brightness-6",
                      kind: .sensor(unit: "", deviceClass: "")),
        ESPHomeEntity(id: EntityID.battery, name: "Battery", diagnostic: true,
                      kind: .sensor(unit: "%", deviceClass: "battery")),
        ESPHomeEntity(id: EntityID.charging, name: "Charging", diagnostic: true,
                      kind: .binarySensor(deviceClass: "battery_charging")),
        ESPHomeEntity(id: EntityID.reload, name: "Reload Dashboard", icon: "mdi:refresh",
                      kind: .button),
    ]

    private static let actions: [ESPHomeAction] = [
        // esphome.<device>_show_url: wake the dashboard on `url` for `duration` seconds
        // (0: until the mode changes or Reload Dashboard is pressed), then go back home.
        ESPHomeAction(name: showURLAction, arguments: [("url", .string), ("duration", .int)]),
    ]

    // MARK: - Lifecycle

    /// Called once the app is past onboarding. Starts the server if the link is enabled and
    /// from then on follows the setting.
    func start(settings: AppSettings, kioskManager: KioskManager, webController: WebViewController) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.kioskManager = kioskManager
        self.webController = webController

        // `objectWillChange` fires before the value is stored, so read on the next main-queue turn.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &observers)
        kioskManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishStates() }
            .store(in: &observers)
        NotificationCenter.default
            .publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .sink { [weak self] _ in self?.publishStates() }
            .store(in: &observers)

        applyConfiguration()
    }

    func appDidBecomeActive() {
        server?.ensureListening()
        publishStates()
    }

    // MARK: - Configuration

    /// Everything that needs the server restarted when it changes.
    private struct Configuration: Equatable {
        var device: ESPHomeDevice
        var key: Data
    }

    private func currentConfiguration() -> Configuration? {
        guard let settings, settings.homeAssistantLinkEnabled,
              let key = Data(base64Encoded: settings.homeAssistantKey), key.count == 32 else { return nil }
        let mac = settings.homeAssistantMACAddress
        let friendlyName = settings.homeAssistantDeviceName.trimmingCharacters(in: .whitespaces)
        let device = ESPHomeDevice(
            name: Self.hostName(from: friendlyName, macAddress: mac),
            friendlyName: friendlyName.isEmpty ? "DashPad" : friendlyName,
            macAddress: mac,
            model: UIDevice.current.model,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
        return Configuration(device: device, key: key)
    }

    /// "Kitchen iPad" becomes "kitchen-ipad-3fa2c1": lowercase letters, digits and hyphens,
    /// with the end of the MAC address so two iPads with the same name stay distinct.
    static func hostName(from friendlyName: String, macAddress: String) -> String {
        let folded = friendlyName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = ""
        for character in folded.unicodeScalars {
            if ("a"..."z").contains(character) || ("0"..."9").contains(character) {
                slug.unicodeScalars.append(character)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "dashpad" }
        // ESPHome names are at most 31 characters.
        return String(slug.prefix(24)) + "-" + macAddress.suffix(6)
    }

    private func settingsChanged() {
        guard currentConfiguration() != runningConfiguration else { return }
        // Typing a device name changes the configuration on every keystroke; restart once it settles.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            self?.applyConfiguration()
        }
    }

    private func applyConfiguration() {
        let configuration = currentConfiguration()
        guard configuration != runningConfiguration else { return }
        stopServer()
        runningConfiguration = configuration
        guard let configuration else { return }

        let server = ESPHomeServer(device: configuration.device, key: configuration.key,
                                   entities: Self.entities, actions: Self.actions)
        server.onStatusChange = { [weak self] in self?.statusChanged($0) }
        server.onCommand = { [weak self] in self?.handle($0) }
        self.server = server

        UIDevice.current.isBatteryMonitoringEnabled = true
        // Camera luminance and battery don't publish changes of their own, so sweep for them.
        stateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.publishStates()
        }
        publishStates()
        server.start()
    }

    private func stopServer() {
        guard server != nil else { return }
        stateTimer?.invalidate()
        disconnectTimer?.invalidate()
        server?.onStatusChange = nil
        server?.stop()
        server = nil
        status = .stopped
        UIDevice.current.isBatteryMonitoringEnabled = false
        // Nothing can change the mode back once the link is off.
        releaseHomeAssistantControl()
    }

    private func statusChanged(_ newStatus: ESPHomeServer.Status) {
        status = newStatus
        if case .listening(let clients) = newStatus, clients > 0 {
            disconnectTimer?.invalidate()
            disconnectTimer = nil
        } else if disconnectTimer == nil {
            disconnectTimer = Timer.scheduledTimer(withTimeInterval: Self.disconnectGrace, repeats: false) { [weak self] _ in
                self?.disconnectTimer = nil
                self?.releaseHomeAssistantControl()
            }
        }
    }

    private func releaseHomeAssistantControl() {
        guard let kioskManager, kioskManager.requestedMode != .auto else { return }
        kioskManager.setRequestedMode(.auto)
    }

    // MARK: - DashPad to Home Assistant

    private func publishStates() {
        guard let server, let kioskManager else { return }

        server.setState(kioskManager.presence.map { .bool($0) }, for: EntityID.presence)

        let display: String
        switch kioskManager.displayState {
        case .active: display = "dashboard"
        case .idle:   display = kioskManager.isNightActive ? "night" : "idle"
        }
        server.setState(.text(display), for: EntityID.display)
        server.setState(.text(kioskManager.requestedMode.rawValue), for: EntityID.mode)
        server.setState(kioskManager.roomLuminance.map { .number(Float($0.rounded())) }, for: EntityID.roomBrightness)

        let device = UIDevice.current
        // -1 means unknown, which is all the simulator ever reports.
        server.setState(device.batteryLevel >= 0 ? .number((device.batteryLevel * 100).rounded()) : nil,
                        for: EntityID.battery)
        switch device.batteryState {
        case .charging, .full: server.setState(.bool(true), for: EntityID.charging)
        case .unplugged:       server.setState(.bool(false), for: EntityID.charging)
        default:               server.setState(nil, for: EntityID.charging)
        }
    }

    // MARK: - Home Assistant to DashPad

    private func handle(_ command: ESPHomeCommand) {
        guard let settings, let kioskManager, let webController else { return }

        switch command {
        case .select(EntityID.mode, let option):
            guard let mode = RequestedMode(rawValue: option) else { return }
            kioskManager.setRequestedMode(mode)

        case .press(EntityID.reload):
            // Ending a hold already sends the dashboard home; otherwise do it here.
            kioskManager.endDashboardHold()
            webController.goHome(url: settings.homeURL)

        case .action(Self.showURLAction, let arguments):
            guard arguments.count == 2,
                  case .string(let text) = arguments[0], case .int(let seconds) = arguments[1],
                  let url = AppSettings.webURL(from: text),
                  // Home Assistant gets no more reach than someone tapping a link on the dashboard.
                  settings.allowsNavigation(to: url) else { return }
            // The hold first: ending an earlier hold sends the dashboard home, and this load
            // has to come after that one to win.
            kioskManager.holdDashboard(for: seconds > 0 ? TimeInterval(seconds) : nil) { [weak webController, weak settings] in
                guard let webController, let settings else { return }
                webController.goHome(url: settings.homeURL)
            }
            webController.show(url)

        default:
            break
        }
        publishStates()
    }
}

// MARK: - Local address

extension HomeAssistantLink {
    /// This iPad's Wi-Fi IPv4 address, for adding the device to Home Assistant by hand when
    /// discovery doesn't find it. Nil when not on Wi-Fi.
    static var wifiAddress: String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }

        var pointer = first
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
