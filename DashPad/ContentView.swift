import SwiftUI

struct ContentView: View {
    @Environment(KioskManager.self) var kioskManager
    @Environment(AppSettings.self) var settings

    var body: some View {
        ZStack {
            // Main content layer
            Group {
                switch kioskManager.displayState {
                case .active:
                    KioskBrowserView()
                case .idle:
                    IdleView()
                }
            }
            .ignoresSafeArea()

            // Invisible 88×88 pt corner tap target (top-right) for secret gesture
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 88, height: 88)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 3) {
                            kioskManager.handleSecretTap()
                        }
                }
                Spacer()
            }
            .ignoresSafeArea()

            // PIN entry overlay
            if kioskManager.showingPINEntry {
                PINEntryOverlay()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(10)
            }

            // Settings panel
            if kioskManager.showingSettings {
                SettingsView()
                    .transition(.move(edge: .trailing).animation(.easeInOut(duration: 0.3)))
                    .zIndex(20)
            }
        }
        .ignoresSafeArea()
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
