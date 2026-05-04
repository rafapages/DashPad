import AVFoundation
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    /// Called when the user completes the final step. The caller is responsible
    /// for persisting the completion flag and dismissing any parent UI.
    var onComplete: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var urlText = ""
    @State private var urlError: String? = nil
    @State private var selectedIdleType: IdleScreenType = .clock
    @State private var cameraAccessDenied = false
    @State private var showingPINSetup = false
    @State private var pinBeforeSetup = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                stepContent
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    // Step 1 manages its own padding so the gradient can go edge-to-edge.
                    // Steps 2–6 are capped at 520 pt so they don't over-stretch on large iPads.
                    .padding(.horizontal, step == 1 ? 0 : 28)
                    .padding(.top, step == 1 ? 0 : 40)
                    .padding(.bottom, step == 1 ? 0 : 32)
                    .frame(maxWidth: step == 1 ? .infinity : 520, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if step >= 2 && step <= 6 {
                progressPills(current: step - 2, total: 5)
                    .padding(.vertical, 24)
            }
        }
        .sheet(isPresented: $showingPINSetup) {
            PINSetupView(savedPIN: Bindable(settings).exitPIN)
        }
        .onChange(of: showingPINSetup) { _, isShowing in
            if !isShowing && settings.exitPIN != pinBeforeSetup {
                advance()
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .onAppear {
            urlText = settings.homeURL
            selectedIdleType = settings.idleScreenType
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: welcomeStep()
        case 2: presenceStep()
        case 3: dashboardURLStep()
        case 4: idleScreenStep()
        case 5: pinStep()
        default: gestureStep()
        }
    }

    // MARK: - Navigation

    private func advance() {
        withAnimation(.spring(duration: 0.35)) {
            step += 1
        }
    }

    private func complete() {
        onComplete()
        dismiss()
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    settings.presenceMode = .automatic
                    advance()
                } else {
                    withAnimation { cameraAccessDenied = true }
                }
            }
        }
    }

    // MARK: - Step 1: Welcome

    private func welcomeStep() -> some View {
        VStack(spacing: 0) {
            // Animated gradient header — edge-to-edge, top corners match the sheet.
            // Adjust the fraction below to change how much of the sheet height it occupies.
            AnimatedBlobGradient()
                .containerRelativeFrame(.vertical) { h, _ in h * 0.5 }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 20, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 20
                ))
                .overlay {
                    ZStack {
                        Image("2-widgets")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        Image("1-frame")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .frame(width: 330)
                }

            // Card body — own horizontal padding so text is inset from the gradient edges
            VStack(spacing: 14) {
                Text("Welcome to DashPad")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Turn your iPad into a dedicated, always-on kiosk display. This takes about a minute to set up, and everything can be changed later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)

            Spacer(minLength: 28)

            Button("Get started") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Step 2: Presence detection

    @ViewBuilder
    private func presenceStep() -> some View {
        VStack(spacing: 24) {
            stepHeader(
                icon: "person.fill.viewfinder",
                title: "Presence detection",
                body: "DashPad can use the front camera to detect when someone is nearby — showing your content when you're present, and switching to an idle screen when you walk away."
            )

            InfoBox(title: "How it works — and what it doesn't do") {
                VStack(alignment: .leading, spacing: 8) {
                    bulletRow("The camera fires for ~3 seconds per sample, then shuts off")
                    bulletRow("Frames are processed on-device and immediately discarded")
                    bulletRow("Nothing is recorded, stored, or sent anywhere")
                    bulletRow("The camera LED is visible every time it activates")
                    bulletRow("Sample rate, timeout, and sensitivity are all configurable")
                }
            }

            if cameraAccessDenied {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Camera access was denied. You can enable it later in iOS Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            footerNote("Not ready to decide? You can skip this and turn it on later in Settings → Presence.")

            ctaRow(
                skipLabel: "Skip for now",
                onSkip: {
                    settings.presenceMode = .alwaysActive
                    advance()
                },
                primaryLabel: cameraAccessDenied ? "Continue" : "Enable & allow access",
                onPrimary: { cameraAccessDenied ? advance() : requestCamera() }
            )
        }
    }

    // MARK: - Step 3: Dashboard URL

    @ViewBuilder
    private func dashboardURLStep() -> some View {
        VStack(spacing: 24) {
            stepHeader(
                icon: "display",
                title: "What would you like to display?",
                body: "Enter the URL of the page you want DashPad to load on startup. This can be any webpage accessible from your network."
            )

            VStack(alignment: .leading, spacing: 6) {
                TextField("http://", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(validateAndAdvance)

                Text("Using Home Assistant? The default address above is already filled in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = urlError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            footerNote("You can change this, add favourites, and restrict which domains the kiosk can navigate to in Settings → Dashboard.")

            Button("Continue") { validateAndAdvance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    private func validateAndAdvance() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            urlError = "Please enter a valid URL starting with http:// or https://"
            return
        }
        urlError = nil
        settings.homeURL = trimmed
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        advance()
    }

    // MARK: - Step 4: Idle screen

    @ViewBuilder
    private func idleScreenStep() -> some View {
        VStack(spacing: 24) {
            stepHeader(
                icon: "clock",
                title: "Idle screen",
                body: "When no one is around, DashPad can show something other than your main display. Pick what makes sense for your setup."
            )

            VStack(spacing: 10) {
                idleOptionCard(
                    type: .clock,
                    description: "A full-screen digital or analogue clock. Low-key and easy to read at a distance."
                )
                idleOptionCard(
                    type: .blank,
                    description: "Solid black screen. Lowest power draw — a good choice for always-on displays."
                )
                idleOptionCard(
                    type: .customURL,
                    description: "Load a different page — a photo slideshow, weather display, or anything you like."
                )
            }

            footerNote("Changeable anytime in Settings → Idle Screen.")

            Button("Continue") {
                settings.idleScreenType = selectedIdleType
                advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private func idleOptionCard(type: IdleScreenType, description: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedIdleType = type } } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedIdleType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIdleType == type ? Color.accentColor : .secondary)
                    .imageScale(.large)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(14)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: PIN lock

    @ViewBuilder
    private func pinStep() -> some View {
        VStack(spacing: 24) {
            stepHeader(
                icon: "lock.fill",
                title: "PIN lock",
                body: "Without a PIN, anyone who knows the gesture can open Settings. If this iPad is in a shared or public space, a PIN is worth setting."
            )

            InfoBox(title: "Good to know") {
                VStack(alignment: .leading, spacing: 8) {
                    bulletRow("PIN is stored securely in the iOS Keychain")
                    bulletRow("If you forget it, Face ID or your device passcode can unlock it")
                    bulletRow("Set or change the PIN anytime in Settings → Kiosk Lock")
                }
            }

            footerNote("Skipping is perfectly fine for a private setup where you're the only user.")

            ctaRow(
                skipLabel: "Skip for now",
                onSkip: advance,
                primaryLabel: "Set a PIN",
                onPrimary: {
                    pinBeforeSetup = settings.exitPIN
                    showingPINSetup = true
                }
            )
        }
    }

    // MARK: - Step 6: Getting back to Settings

    @ViewBuilder
    private func gestureStep() -> some View {
        VStack(spacing: 28) {
            stepHeader(
                icon: "hand.tap",
                title: "Getting back to Settings",
                body: "Once DashPad is running, the interface disappears so nothing gets in the way. Here's how to get back when you need to:"
            )

            VStack(spacing: 12) {
                gestureRow(
                    icon: "hand.tap",
                    title: "Triple-tap the bottom-right corner",
                    description: "Three quick taps opens the PIN prompt (if set), then takes you straight to Settings."
                )
                gestureRow(
                    icon: "lock.open.fill",
                    title: "Forgot your PIN?",
                    description: "Tap 'Forgot PIN?' on the lock screen — Face ID or your device passcode will unlock it."
                )
            }

            footerNote("You can re-run this setup anytime from Settings → Setup assistant.")

            Button("All done — open my display") { complete() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    private func gestureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared components

    private func stepHeader(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ctaRow(
        skipLabel: String,
        onSkip: @escaping () -> Void,
        primaryLabel: String,
        onPrimary: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(skipLabel, action: onSkip)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            Button(primaryLabel, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Progress pills

    private func progressPills(current: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 24 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - InfoBox

private struct InfoBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            OnboardingView(onComplete: {})
                .environment(AppSettings())
        }
}
