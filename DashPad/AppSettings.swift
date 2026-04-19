import Foundation
import Security

@Observable
class AppSettings {
    // MARK: - Persisted settings

    var homeURL: String { didSet { save(homeURL, key: .homeURL) } }
    var idleTimeout: Double { didSet { save(idleTimeout, key: .idleTimeout) } }
    var idleScreenType: IdleScreenType { didSet { save(idleScreenType.rawValue, key: .idleScreenType) } }
    var idleCustomURL: String { didSet { save(idleCustomURL, key: .idleCustomURL) } }
    var clockStyle: ClockStyle { didSet { save(clockStyle.rawValue, key: .clockStyle) } }
    var idleBrightness: Double { didSet { save(idleBrightness, key: .idleBrightness) } }
    var activeBrightness: Double { didSet { save(activeBrightness, key: .activeBrightness) } }
    var lightThreshold: Double { didSet { save(lightThreshold, key: .lightThreshold) } }
    var cameraSampleRate: Double { didSet { save(cameraSampleRate, key: .cameraSampleRate) } }
    var allowedDomains: String { didSet { save(allowedDomains, key: .allowedDomains) } }
    var customCSS: String { didSet { save(customCSS, key: .customCSS) } }
    var customJS: String { didSet { save(customJS, key: .customJS) } }

    // PIN is a stored property backed by Keychain via didSet
    var exitPIN: String {
        didSet { KeychainHelper.write(key: "com.rafapages.dashpad.exitPIN", value: exitPIN) }
    }

    init() {
        let ud = UserDefaults.standard
        homeURL = ud.string(forKey: Key.homeURL.rawValue) ?? "http://homeassistant.local:8123"
        idleTimeout = ud.optionalDouble(forKey: Key.idleTimeout.rawValue) ?? 60.0
        idleScreenType = IdleScreenType(rawValue: ud.string(forKey: Key.idleScreenType.rawValue) ?? "") ?? .clock
        idleCustomURL = ud.string(forKey: Key.idleCustomURL.rawValue) ?? ""
        clockStyle = ClockStyle(rawValue: ud.string(forKey: Key.clockStyle.rawValue) ?? "") ?? .digital
        idleBrightness = ud.optionalDouble(forKey: Key.idleBrightness.rawValue) ?? 0.15
        activeBrightness = ud.optionalDouble(forKey: Key.activeBrightness.rawValue) ?? 0.80
        lightThreshold = ud.optionalDouble(forKey: Key.lightThreshold.rawValue) ?? 0.05
        cameraSampleRate = ud.optionalDouble(forKey: Key.cameraSampleRate.rawValue) ?? 2.0
        allowedDomains = ud.string(forKey: Key.allowedDomains.rawValue) ?? ""
        customCSS = ud.string(forKey: Key.customCSS.rawValue) ?? ""
        customJS = ud.string(forKey: Key.customJS.rawValue) ?? ""
        exitPIN = KeychainHelper.read(key: "com.rafapages.dashpad.exitPIN") ?? ""
    }

    var allowedDomainList: [String] {
        allowedDomains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Private

    private enum Key: String {
        case homeURL, idleTimeout, idleScreenType, idleCustomURL, clockStyle
        case idleBrightness, activeBrightness, lightThreshold, cameraSampleRate
        case allowedDomains, customCSS, customJS
    }

    private func save(_ value: some Any, key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}

// MARK: - Supporting types

enum IdleScreenType: String, CaseIterable {
    case clock, blank, customURL

    var displayName: String {
        switch self {
        case .clock: "Clock"
        case .blank: "Blank"
        case .customURL: "Custom URL"
        }
    }
}

enum ClockStyle: String, CaseIterable {
    case digital, analog

    var displayName: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        }
    }
}

// MARK: - Helpers

private extension UserDefaults {
    func optionalDouble(forKey key: String) -> Double? {
        object(forKey: key) != nil ? double(forKey: key) : nil
    }
}

private enum KeychainHelper {
    static func write(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
