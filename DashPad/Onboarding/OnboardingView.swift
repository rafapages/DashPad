import AVFoundation
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    var onComplete: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var slideForward = true
    @State private var urlText = ""
    @State private var urlError: String? = nil
    @State private var selectedIdleType: IdleScreenType = .clock
    @State private var cameraAccessDenied = false
    @State private var showingPINSetup = false
    @State private var pinBeforeSetup = ""

    var body: some View {
        VStack(spacing: 0) {
            // Back button — visible on steps 2–6
            if step > 1 {
                HStack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.bottom, 4)
            }

            // Scrollable step content (no buttons — those are in the fixed footer)
            ScrollView {
                VStack(spacing: 0) {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .padding(.horizontal, step == 1 ? 0 : 28)
                        .padding(.top, step == 1 ? 0 : 24)
                        .frame(maxWidth: step == 1 ? .infinity : 520, alignment: .center)
                }
                .frame(maxWidth: .infinity)
            }

            // Fixed footer: progress dots + CTA buttons
            VStack(spacing: 12) {
                if step >= 2 && step <= 6 {
                    progressPills(current: step - 2, total: 5)
                }
                footerButtons
                    .padding(.horizontal, 28)
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
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

    // MARK: - Footer buttons

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case 1:
            primaryButton("Get started", action: advance)
                .frame(maxWidth: .infinity)
        case 2:
            HStack(spacing: 8) {
                secondaryButton("Skip for now") {
                    settings.presenceMode = .alwaysActive
                    advance()
                }
                primaryButton(cameraAccessDenied ? "Continue" : "Enable & allow access") {
                    cameraAccessDenied ? advance() : requestCamera()
                }
            }
        case 3:
            primaryButton("Continue", action: validateAndAdvance)
                .frame(maxWidth: .infinity)
        case 4:
            primaryButton("Continue") {
                settings.idleScreenType = selectedIdleType
                advance()
            }
            .frame(maxWidth: .infinity)
        case 5:
            HStack(spacing: 8) {
                secondaryButton("Skip for now", action: advance)
                primaryButton("Set a PIN") {
                    pinBeforeSetup = settings.exitPIN
                    showingPINSetup = true
                }
            }
        default:
            primaryButton("All done — open my display", action: complete)
                .frame(maxWidth: .infinity)
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }

    // MARK: - Navigation

    private func advance() {
        withAnimation(.spring(duration: 0.35)) {
            slideForward = true
            step += 1
        }
    }

    private func goBack() {
        withAnimation(.spring(duration: 0.35)) {
            slideForward = false
            step -= 1
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

    // MARK: - Step content (buttons are in the fixed footer, not here)

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

    // MARK: - Step 1: Welcome

    private func welcomeStep() -> some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 2: Presence detection

    @ViewBuilder
    private func presenceStep() -> some View {
        VStack(spacing: 20) {
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
        }
    }

    // MARK: - Step 3: Dashboard URL

    @ViewBuilder
    private func dashboardURLStep() -> some View {
        VStack(spacing: 20) {
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
        }
    }

    // MARK: - Step 4: Idle screen

    @ViewBuilder
    private func idleScreenStep() -> some View {
        VStack(spacing: 20) {
            stepHeader(
                icon: "clock",
                title: "Idle screen",
                body: "What should DashPad show when no one is around?"
            )

            VStack(spacing: 10) {
                idleOptionCard(type: .clock,     description: "Digital or analogue clock — easy to read at a distance.")
                idleOptionCard(type: .blank,     description: "Solid black screen — lowest power draw.")
                idleOptionCard(type: .customURL, description: "Load a different page — slideshow, weather, or anything you like.")
            }

            footerNote("Changeable anytime in Settings → Idle Screen.")
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: PIN lock

    @ViewBuilder
    private func pinStep() -> some View {
        VStack(spacing: 20) {
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
        }
    }

    // MARK: - Step 6: Getting back to Settings

    @ViewBuilder
    private func gestureStep() -> some View {
        VStack(spacing: 20) {
            stepHeader(
                icon: "hand.tap",
                title: "Getting back to Settings",
                body: "Once DashPad is running, the interface disappears so nothing gets in the way. Here's how to get back:"
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
        }
    }

    private func gestureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
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
            Text("•").foregroundStyle(.secondary).font(.callout)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
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
            Text(title).font(.callout.weight(.semibold))
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
