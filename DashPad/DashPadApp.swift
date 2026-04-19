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
