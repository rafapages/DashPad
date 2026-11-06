// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// DashPadApp.swift - @main entry point. Owns AppSettings, KioskManager and WebViewController as
// @StateObject so they live for the full lifetime of the app and are never recreated during
// view updates.

import SwiftUI

@main
struct DashPadApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var kioskManager = KioskManager()
    @StateObject private var webController = WebViewController()

    init() {
        WhatsNew.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(kioskManager)
                .environmentObject(webController)
        }
    }
}
