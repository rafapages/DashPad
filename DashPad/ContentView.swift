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

            // Invisible 88×88 pt corner tap target for secret gesture
            Color.clear
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    kioskManager.handleSecretTap()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.settingsCorner.alignment)
                .ignoresSafeArea()

            // PIN entry overlay
            if kioskManager.showingPINEntry {
                PINEntryOverlay()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(10)
            }
        }
        // UIStatusBarHidden in Info.plist only covers launch; SwiftUI's hosting controller
        // decides afterwards, so it has to be requested explicitly. The idle screen always hides
        // it; the dashboard follows the user's setting.
        .statusBarHidden(settings.hideStatusBar || kioskManager.displayState == .idle)
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
        // iPadOS Auto-Lock would otherwise sleep and lock a wall-mounted kiosk after a few
        // minutes without touches. Dimming on idle is KioskManager's job, not the system's.
        .onChangeCompat(of: settings.preventAutoLock) { applyIdleTimer($0) }
        .onAppear {
            applyIdleTimer(settings.preventAutoLock)
            if hasCompletedOnboarding {
                kioskManager.start(settings: settings)
            } else {
                showingOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-asserted on every activation: the flag is not guaranteed to survive the app
            // being backgrounded (e.g. Control Center, a call, or the user leaving Guided Access).
            applyIdleTimer(settings.preventAutoLock)
            kioskManager.evaluateSchedule()
        }
    }

    private func applyIdleTimer(_ preventAutoLock: Bool) {
        UIApplication.shared.isIdleTimerDisabled = preventAutoLock
    }
}

private extension SettingsCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(KioskManager())
        .environmentObject(WebViewController())
}
