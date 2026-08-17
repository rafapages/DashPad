// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// AppSettings.swift - single source of truth for all user configuration.
// Every property persists immediately via didSet → UserDefaults (or Keychain for the PIN).
// Injected into the SwiftUI environment at the root; read by views and KioskManager alike.

import Combine
import Foundation
import Security

class AppSettings: ObservableObject {
    // MARK: - Persisted settings

    @Published var homeURL: String { didSet { save(homeURL, key: .homeURL) } }
    @Published var idleTimeout: Double { didSet { save(idleTimeout, key: .idleTimeout) } }
    @Published var idleScreenType: IdleScreenType { didSet { save(idleScreenType.rawValue, key: .idleScreenType) } }
    @Published var idleCustomURL: String { didSet { save(idleCustomURL, key: .idleCustomURL) } }
    @Published var clockStyle: ClockStyle { didSet { save(clockStyle.rawValue, key: .clockStyle) } }
    @Published var idleBrightness: Double { didSet { save(idleBrightness, key: .idleBrightness) } }
    @Published var activeBrightness: Double { didSet { save(activeBrightness, key: .activeBrightness) } }
    @Published var presenceMode: PresenceMode { didSet { save(presenceMode.rawValue, key: .presenceMode) } }
    @Published var cameraSampleRate: Double { didSet { save(cameraSampleRate, key: .cameraSampleRate) } }
    @Published var nightSampleRate: Double { didSet { save(nightSampleRate, key: .nightSampleRate) } }
    @Published var presenceRecheckInterval: Double { didSet { save(presenceRecheckInterval, key: .presenceRecheckInterval) } }
    @Published var darkLuminanceThreshold: Double { didSet { save(darkLuminanceThreshold, key: .darkLuminanceThreshold) } }
    @Published var detectionMode: DetectionMode { didSet { save(detectionMode.rawValue, key: .detectionMode) } }
    @Published var allowedDomains: String { didSet { save(allowedDomains, key: .allowedDomains) } }
    @Published var customCSS: String { didSet { save(customCSS, key: .customCSS) } }
    @Published var customJS: String { didSet { save(customJS, key: .customJS) } }
    @Published var favouriteURLs: [String] { didSet { save(favouriteURLs, key: .favouriteURLs) } }
    @Published var weeklySchedule: WeeklySchedule { didSet { saveCodable(weeklySchedule, key: .weeklySchedule) } }
    @Published var manualWakeTimeout: Double { didSet { save(manualWakeTimeout, key: .manualWakeTimeout) } }

    // PIN is stored in Keychain
    @Published var exitPIN: String {
        didSet { KeychainHelper.write(key: Self.pinKeychainKey, value: exitPIN) }
    }

    /// Digits in a newly created PIN. `PINSetupView` is the only writer of a non-empty `exitPIN`,
    /// so this is the length of every PIN this app creates - both the setup keypad and the entry
    /// overlay size themselves from it rather than hard-coding a count of their own.
    static let pinLength = 4

    private static let pinKeychainKey = "com.rafapages.dashpad.exitPIN"
    /// Owned by `ContentView`'s `@AppStorage`; read here only to recognise a fresh install.
    private static let onboardingCompletedKey = "hasCompletedOnboarding"

    init() {
        let ud = UserDefaults.standard

        // Migration: if presenceMode not yet saved, derive from legacy presenceEnabled
        if ud.object(forKey: Key.presenceMode.rawValue) == nil {
            let legacy = ud.object(forKey: "presenceEnabled") as? Bool ?? true
            ud.set(legacy ? PresenceMode.automatic.rawValue : PresenceMode.alwaysActive.rawValue,
                   forKey: Key.presenceMode.rawValue)
        }

        homeURL = ud.string(forKey: Key.homeURL.rawValue) ?? "http://homeassistant.local:8123"
        idleTimeout = ud.optionalDouble(forKey: Key.idleTimeout.rawValue) ?? 60.0
        idleScreenType = IdleScreenType(rawValue: ud.string(forKey: Key.idleScreenType.rawValue) ?? "") ?? .clock
        idleCustomURL = ud.string(forKey: Key.idleCustomURL.rawValue) ?? ""
        clockStyle = ClockStyle(rawValue: ud.string(forKey: Key.clockStyle.rawValue) ?? "") ?? .digital
        idleBrightness = ud.optionalDouble(forKey: Key.idleBrightness.rawValue) ?? 0.15
        activeBrightness = ud.optionalDouble(forKey: Key.activeBrightness.rawValue) ?? 0.80
        presenceMode = PresenceMode(rawValue: ud.string(forKey: Key.presenceMode.rawValue) ?? "") ?? .automatic
        cameraSampleRate = ud.optionalDouble(forKey: Key.cameraSampleRate.rawValue) ?? 5.0
        nightSampleRate = ud.optionalDouble(forKey: Key.nightSampleRate.rawValue) ?? 60.0
        presenceRecheckInterval = ud.optionalDouble(forKey: Key.presenceRecheckInterval.rawValue) ?? 30.0
        darkLuminanceThreshold = ud.optionalDouble(forKey: Key.darkLuminanceThreshold.rawValue) ?? 20.0
        detectionMode = DetectionMode(rawValue: ud.string(forKey: Key.detectionMode.rawValue) ?? "") ?? .body
        allowedDomains = ud.string(forKey: Key.allowedDomains.rawValue) ?? ""
        customCSS = ud.string(forKey: Key.customCSS.rawValue) ?? ""
        customJS = ud.string(forKey: Key.customJS.rawValue) ?? ""
        favouriteURLs = ud.stringArray(forKey: Key.favouriteURLs.rawValue) ?? []
        weeklySchedule = Self.decodeCodable(WeeklySchedule.self, forKey: Key.weeklySchedule.rawValue) ?? WeeklySchedule()
        manualWakeTimeout = ud.optionalDouble(forKey: Key.manualWakeTimeout.rawValue) ?? 120.0

        // Keychain items outlive app deletion, so a reinstall would otherwise come back already
        // locked by a PIN from the previous install - one the user may not remember, and which
        // makes onboarding's PIN step look broken. An unfinished onboarding means a fresh start.
        if !ud.bool(forKey: Self.onboardingCompletedKey) {
            KeychainHelper.delete(key: Self.pinKeychainKey)
        }
        exitPIN = KeychainHelper.read(key: Self.pinKeychainKey) ?? ""
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
        case presenceEnabled // legacy key - do not use, kept for migration reads only
        case presenceMode, weeklySchedule, manualWakeTimeout
        case idleBrightness, activeBrightness, cameraSampleRate, nightSampleRate
        case presenceRecheckInterval, darkLuminanceThreshold
        case allowedDomains, customCSS, customJS, favouriteURLs, detectionMode
    }

    private func save(_ value: some Any, key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    // UserDefaults cannot store arbitrary Codable structs directly, so we JSON-encode to Data.
    private func saveCodable<T: Codable>(_ value: T, key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key.rawValue)
        }
    }

    private static func decodeCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Supporting types

enum PresenceMode: String, CaseIterable, Codable {
    case automatic, schedule, alwaysActive

    var displayName: String {
        switch self {
        case .automatic:    "Automatic (Camera)"
        case .schedule:     "Schedule"
        case .alwaysActive: "Always Active"
        }
    }
}

struct ScheduleWindow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startMinute: Int   // 0–1439 (minutes since midnight)
    var endMinute: Int     // 0–1439; endMinute < startMinute means the window spans midnight

    var spansMidnight: Bool { endMinute < startMinute }

    func isActive(at minuteOfDay: Int) -> Bool {
        if spansMidnight {
            // e.g. 22:00–07:00: active from start until midnight, and again from midnight until end.
            return minuteOfDay >= startMinute || minuteOfDay < endMinute
        } else {
            return minuteOfDay >= startMinute && minuteOfDay < endMinute
        }
    }
}

struct WeeklySchedule: Codable, Equatable {
    var sameEveryDay: Bool = true
    /// Index 0 = Sunday … 6 = Saturday, matching `Calendar.component(.weekday) - 1`.
    /// When `sameEveryDay` is true only `windows[0]` is evaluated.
    var windows: [[ScheduleWindow]] = Array(repeating: [], count: 7)
}

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

enum DetectionMode: String, CaseIterable {
    case body, face

    var displayName: String {
        switch self {
        case .body: "Body"
        case .face: "Face"
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

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
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
