// ContentView.swift — root view; a thin switcher between KioskBrowserView (active) and
// IdleView (idle). All logic lives in KioskManager; this file contains no business logic.

import SwiftUI

struct ContentView: View {
    @Environment(KioskManager.self) var kioskManager
    @Environment(AppSettings.self) var settings

    var body: some View {
        ZStack {
            // WebView stays resident so returning to active never triggers a reload
            KioskBrowserView()

            if kioskManager.displayState == .idle {
                IdleView()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Both calls are safe here: each is guarded to its own presence mode,
                        // so only one will act. Camera mode uses handleScreenTap(); schedule
                        // mode uses manualWake(). Always-active mode never shows the idle screen.
                        kioskManager.handleScreenTap()
                        kioskManager.manualWake()
                    }
            }

            // Invisible 88×88 pt corner tap target (bottom-right) for secret gesture
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 88, height: 88)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 3) {
                            kioskManager.handleSecretTap()
                        }
                }
            }
            .ignoresSafeArea()

            // PIN entry overlay
            if kioskManager.showingPINEntry {
                PINEntryOverlay()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(10)
            }
        }
        .sheet(isPresented: Bindable(kioskManager).showingSettings) {
            SettingsView()
        }
        .onAppear {
            kioskManager.start(settings: settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            kioskManager.evaluateSchedule()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(KioskManager())
}
