// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ContentView.swift - root view; a thin switcher between KioskBrowserView (active) and
// IdleView (idle). All logic lives in KioskManager; this file contains no business logic.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var kioskManager: KioskManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var webController: WebViewController
    @EnvironmentObject var homeAssistantLink: HomeAssistantLink

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
                        // And when Home Assistant asked for this idle screen, in any mode.
                        kioskManager.wakeFromRequestedIdle()
                    }
            }

            // Invisible 88×88 pt corner tap target for secret gesture
            CornerTapTarget { kioskManager.handleSecretTap() }
                .frame(width: 88, height: 88)
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
        // A cover rather than a sheet: the setup flow shows each step beside a live picture of
        // it, which needs the whole screen, and it was never dismissible by swipe anyway.
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(onComplete: {
                hasCompletedOnboarding = true
                // Deferred from onAppear: the presence mode the user just chose is now stored,
                // and the setup flow is no longer there for the camera dialog to appear behind.
                kioskManager.start(settings: settings)
                startHomeAssistantLink()
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
                startHomeAssistantLink()
            } else {
                showingOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-asserted on every activation: the flag is not guaranteed to survive the app
            // being backgrounded (e.g. Control Center, a call, or the user leaving Guided Access).
            applyIdleTimer(settings.preventAutoLock)
            kioskManager.evaluateSchedule()
            kioskManager.evaluateNight()
            homeAssistantLink.appDidBecomeActive()
        }
    }

    /// After onboarding, like the presence pipeline: listening on the network can raise the
    /// Local Network prompt, which must not appear behind the setup sheet.
    private func startHomeAssistantLink() {
        homeAssistantLink.start(settings: settings, kioskManager: kioskManager, webController: webController)
    }

    private func applyIdleTimer(_ preventAutoLock: Bool) {
        UIApplication.shared.isIdleTimerDisabled = preventAutoLock
    }
}

/// The secret corner target as a real UIView with a UIKit triple-tap recognizer.
/// A SwiftUI `Color.clear` with `onTapGesture(count: 3)` drawn over the dashboard's WKWebView
/// never fired on iPadOS 15 (issue #7). A UIView is hit-tested by UIKit itself, the same way on
/// every iOS release, so it no longer depends on how SwiftUI routes touches over a
/// UIViewRepresentable. Like the old target it swallows taps on whatever lies beneath it.
private struct CornerTapTarget: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fire))
        tap.numberOfTapsRequired = 3
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
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
        .environmentObject(HomeAssistantLink())
}
