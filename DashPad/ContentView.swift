import SwiftUI

struct ContentView: View {
    @Environment(KioskManager.self) var kioskManager
    @Environment(AppSettings.self) var settings

    var body: some View {
        ZStack {
            // WebView stays resident so returning to active never triggers a reload
            KioskBrowserView()
                .ignoresSafeArea()

            if kioskManager.displayState == .idle {
                IdleView()
                    .ignoresSafeArea()
                    .transition(.opacity)
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
        .ignoresSafeArea()
        .sheet(isPresented: Bindable(kioskManager).showingSettings) {
            SettingsView()
        }
        .onAppear {
            kioskManager.start(settings: settings)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(KioskManager())
}
