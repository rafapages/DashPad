// DashPadApp.swift — @main entry point. Owns AppSettings and KioskManager as @State so they
// live for the full lifetime of the app and are never recreated during view updates.

import SwiftUI

@main
struct DashPadApp: App {
    @State private var settings = AppSettings()
    @State private var kioskManager = KioskManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(kioskManager)
        }
    }
}
