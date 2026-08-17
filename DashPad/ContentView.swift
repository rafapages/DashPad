// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ContentView.swift - root view; a thin switcher between KioskBrowserView (active) and
// IdleView (idle). All logic lives in KioskManager; this file contains no business logic.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var kioskManager: KioskManager
    @EnvironmentObject var settings: AppSettings

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

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
        .sheet(isPresented: $kioskManager.showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onComplete: {
                hasCompletedOnboarding = true
                // Deferred from onAppear: the presence mode the user just chose is now stored,
                // and there is no longer a sheet for the camera dialog to appear behind.
                kioskManager.start(settings: settings)
            })
            .environmentObject(settings)
            .environmentObject(kioskManager)
        }
        .onAppear {
            if hasCompletedOnboarding {
                kioskManager.start(settings: settings)
            } else {
                showingOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            kioskManager.evaluateSchedule()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(KioskManager())
}
