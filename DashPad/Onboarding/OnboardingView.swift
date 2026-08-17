// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

import AVFoundation
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    var onComplete: () -> Void
    /// `true` when launched from Settings → Setup assistant rather than on a first run. A re-run
    /// starts from the configuration that already exists instead of demanding every choice again,
    /// and can be left without walking to the end.
    var isRerun: Bool = false

    /// Last step in the flow. `advance()` will not go past it.
    private static let lastStep = 6
    /// Pre-filled by the Home Assistant card, and recognised on a re-run to restore that choice.
    private static let homeAssistantDefaultURL = "http://homeassistant.local:8123"

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var kioskManager: KioskManager
    @Environment(\.dismiss) private var dismiss

    private enum URLSetupMode { case homeAssistant, website }

    @State private var step = 1
    @State private var slideForward = true
    @State private var urlText = ""
    @State private var urlError: String? = nil
    @State private var urlSetupMode: URLSetupMode? = nil
    @State private var selectedIdleType: IdleScreenType = .clock
    /// Idle screen URL, only collected when `selectedIdleType == .customURL`.
    @State private var idleURLText = ""
    @State private var idleURLError: String? = nil
    @State private var showingPINSetup = false
    /// Set by `PINSetupView`'s completion callback, consumed when its sheet finishes dismissing.
    @State private var didSetPIN = false
    /// Read once when the flow appears, and again after a request resolves. Determines whether
    /// step 2 can still raise the system dialog or has to explain an existing decision.
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// Height of the step ScrollView's viewport, measured for the iOS 16 fallback in
    /// `welcomeStep()`. Unused on iOS 17+, where `containerRelativeFrame` reads it natively.
    @State private var scrollViewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Back on steps 2–6; Close only on a re-run, where the flow is not a gate to the app
            // and walking every step just to get out would mean re-answering everything.
            if step > 1 || isRerun {
                HStack {
                    if step > 1 {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                    }
                    Spacer()
                    if isRerun {
                        // "Close", not "Cancel": each step applies its change as you pass it, so
                        // leaving early keeps what was already set rather than undoing it.
                        Button("Close") { dismiss() }
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .padding(.trailing, 20)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 4)
            }

            // Scrollable step content (no buttons - those are in the fixed footer)
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
            .measureContainerHeight()
            .onPreferenceChange(ContainerHeightKey.self) { scrollViewportHeight = $0 }

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
            PINSetupView(savedPIN: $settings.exitPIN, onSet: { didSetPIN = true })
        }
        .onChangeCompat(of: showingPINSetup) { isShowing in
            // Advancing on dismissal rather than from the callback keeps the step transition
            // from animating underneath the sheet on its way out.
            if !isShowing && didSetPIN {
                didSetPIN = false
                advance(from: 5)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .onAppear {
            // A first run demands an explicit dashboard choice, so it starts empty. A re-run
            // starts from what is already configured - otherwise reaching any later step means
            // retyping the dashboard URL, or silently replacing it with the Home Assistant
            // default, because step 3 cannot be passed without picking a card.
            if isRerun, !settings.homeURL.trimmingCharacters(in: .whitespaces).isEmpty {
                urlText = settings.homeURL.trimmingCharacters(in: .whitespaces)
                urlSetupMode = urlText == Self.homeAssistantDefaultURL ? .homeAssistant : .website
            } else {
                urlText = ""
                urlSetupMode = nil
            }
            urlError = nil
            selectedIdleType = settings.idleScreenType
            idleURLText = settings.idleCustomURL
            idleURLError = nil
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    // MARK: - Footer buttons

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case 1:
            primaryButton("Get started") { advance(from: 1) }
                .frame(maxWidth: .infinity)
        case 2:
            primaryButton("Continue", action: continueFromPresenceStep)
                .frame(maxWidth: .infinity)
        case 3:
            primaryButton("Continue", action: validateAndAdvance)
                .frame(maxWidth: .infinity)
                .disabled(urlSetupMode == nil)
        case 4:
            primaryButton("Continue", action: continueFromIdleStep)
                .frame(maxWidth: .infinity)
        case 5:
            HStack(spacing: 8) {
                secondaryButton("Skip for now") { advance(from: 5) }
                primaryButton("Set a PIN") { showingPINSetup = true }
            }
        default:
            primaryButton("All done, open my display", action: complete)
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
        guard step < Self.lastStep else { return }
        withAnimation(.spring(duration: 0.35)) {
            slideForward = true
            step += 1
        }
    }

    /// Footer-button entry point. A step transition takes 0.35 s to render, and on the slower
    /// iPads this app supports a second tap can land before the footer has swapped to the next
    /// step's button - advancing twice and skipping a step. Passing the step the button was drawn
    /// for makes the stale tap a no-op.
    private func advance(from expectedStep: Int) {
        guard step == expectedStep else { return }
        advance()
    }

    private func goBack() {
        guard step > 1 else { return }
        withAnimation(.spring(duration: 0.35)) {
            slideForward = false
            step -= 1
        }
    }

    private func complete() {
        // Inner sheet first: on a re-run `onComplete` closes the settings sheet that presents this
        // one, and tearing the presenter down while this sheet is still dismissing can strand the
        // presentation.
        dismiss()
        onComplete()
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// Step 2's primary action. `requestAccess` only raises the system dialog while the status is
    /// `.notDetermined`; in every other state it returns the standing decision immediately, so
    /// calling it unconditionally would make this step look inert. Each state is handled instead.
    private func continueFromPresenceStep() {
        switch cameraStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraStatus = granted ? .authorized : .denied
                    if granted {
                        applyPresenceMode(.automatic)
                    } else {
                        fallBackIfCameraModeUnusable()
                    }
                    advance(from: 2)
                }
            }
        case .denied, .restricted:
            // The step already explains this (see `presenceStatusNote`), so just move on.
            fallBackIfCameraModeUnusable()
            advance(from: 2)
        default:
            // Already authorized: nothing to ask, and the mode is whatever the user chose.
            advance(from: 2)
        }
    }

    /// Automatic mode cannot detect anything without camera access, so swap it out rather than
    /// leaving a mode that silently never fires. Schedule mode, which the user can only have
    /// picked deliberately in Settings, does not use the camera and is left alone.
    private func fallBackIfCameraModeUnusable() {
        guard settings.presenceMode == .automatic else { return }
        applyPresenceMode(.alwaysActive)
    }

    /// Persists the mode and restarts the pipeline behind it. `AppSettings` alone is not enough:
    /// `KioskManager` reads the mode once at startup and otherwise has to be told.
    private func applyPresenceMode(_ mode: PresenceMode) {
        settings.presenceMode = mode
        kioskManager.setPresenceMode(mode)
    }

    /// Shared by the dashboard and idle URL fields. A scheme prefix on its own is not enough:
    /// "http://" passes a `hasPrefix` check, is stored happily, and then fails to load with
    /// nothing to explain why - so a host is required too.
    private func normalizedURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty
        else { return nil }
        return trimmed
    }

    private static let urlErrorMessage =
        "Please enter a valid URL starting with http:// or https:// - for example http://192.168.1.10:8123"

    private func validateAndAdvance() {
        guard let url = normalizedURL(from: urlText) else {
            urlError = Self.urlErrorMessage
            return
        }
        urlError = nil
        settings.homeURL = url
        resignKeyboard()
        advance(from: 3)
    }

    /// Step 4. The Custom URL option is only committed once it has a URL to load - otherwise the
    /// mode is saved with an empty `idleCustomURL`, and `IdleView` quietly shows the clock while
    /// Settings reports Custom URL.
    private func continueFromIdleStep() {
        if selectedIdleType == .customURL {
            guard let url = normalizedURL(from: idleURLText) else {
                idleURLError = Self.urlErrorMessage
                return
            }
            idleURLError = nil
            settings.idleCustomURL = url
        }
        settings.idleScreenType = selectedIdleType
        resignKeyboard()
        advance(from: 4)
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
                .relativeContainerHeight(0.5, measuredContainerHeight: scrollViewportHeight)
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
                body: "DashPad can use the front camera to detect when someone is nearby, showing your content when you're present and switching to an idle screen when you walk away."
            )

            InfoBox(title: "How it works, and what it doesn't do") {
                VStack(alignment: .leading, spacing: 8) {
                    bulletRow("The camera fires for ~3 seconds per sample, then shuts off")
                    bulletRow("Frames are processed on-device and immediately discarded")
                    bulletRow("Nothing is recorded, stored, or sent anywhere")
                    bulletRow("The camera LED is visible every time it activates")
                    bulletRow("Sample rate, timeout, and sensitivity are all configurable")
                }
            }

            presenceStatusNote
        }
    }

    /// What this step will actually do, given the standing camera decision. Only the
    /// `.notDetermined` case leads to the system dialog; the others would otherwise leave the
    /// Continue button looking like it does nothing.
    @ViewBuilder
    private var presenceStatusNote: some View {
        switch cameraStatus {
        case .denied, .restricted:
            noteBox(icon: "exclamationmark.triangle.fill", tint: .orange, text: cameraUnavailableMessage)
        case .authorized where settings.presenceMode != .automatic:
            // Access is granted but the user is on a non-camera mode, so nothing here changes it -
            // and switching it for them would undo a choice they made deliberately in Settings.
            noteBox(
                icon: "info.circle.fill",
                tint: .accentColor,
                text: "Camera access is already allowed, but presence detection is off because Presence Mode is set to \(settings.presenceMode.displayName). Choose Automatic in Settings → Presence to turn it on."
            )
        default:
            Text("If you decline, presence detection stays off — you can turn it on anytime in Settings → Presence.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noteBox(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    /// `.restricted` means camera use is blocked device-wide, which the app's own permission
    /// row in iOS Settings cannot fix - so the two states are worded differently.
    private var cameraUnavailableMessage: String {
        cameraStatus == .restricted
            ? "Camera use is switched off for this iPad by Screen Time or a device management profile. Presence detection will stay off and DashPad will keep the dashboard always on."
            : "Camera access for DashPad is currently off, so presence detection will stay off. You can allow it in iOS Settings → Privacy & Security → Camera, then pick Automatic in Settings → Presence."
    }

    // MARK: - Step 3: Dashboard URL

    @ViewBuilder
    private func dashboardURLStep() -> some View {
        VStack(spacing: 20) {
            stepHeader(
                icon: "display",
                title: "What would you like to display?",
                body: "Choose what DashPad should load on startup."
            )

            VStack(spacing: 10) {
                urlModeCard(
                    mode: .homeAssistant,
                    icon: "homekit",
                    title: "Home Assistant",
                    description: "Pre-fills the default local address. You can still edit it if your setup is different."
                )
                urlModeCard(
                    mode: .website,
                    icon: "globe",
                    title: "A website or custom URL",
                    description: "Enter any URL accessible from your network."
                )
            }

            if urlSetupMode != nil {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("http://", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(validateAndAdvance)

                    if let error = urlError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footerNote("You can change this, add favourites, and restrict which domains the kiosk can navigate to in Settings → Dashboard.")
        }
    }

    private func urlModeCard(mode: URLSetupMode, icon: String, title: String, description: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                urlSetupMode = mode
                urlText = mode == .homeAssistant ? "http://homeassistant.local:8123" : ""
                urlError = nil
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: urlSetupMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(urlSetupMode == mode ? Color.accentColor : .secondary)
                    .imageScale(.large)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
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
                idleOptionCard(type: .clock,     description: "Digital or analogue clock, easy to read at a distance.")
                idleOptionCard(type: .blank,     description: "Solid black screen for the lowest power draw.")
                idleOptionCard(type: .customURL, description: "Load a different page: a slideshow, weather, or anything you like.")
            }

            if selectedIdleType == .customURL {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("http://", text: $idleURLText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(continueFromIdleStep)

                    if let error = idleURLError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                    description: "Tap 'Forgot PIN?' on the lock screen, then Face ID or your device passcode will unlock it."
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
                .environmentObject(AppSettings())
                .environmentObject(KioskManager())
        }
}
