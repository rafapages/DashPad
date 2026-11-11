// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// OnboardingView.swift - the setup flow: its steps, what each one saves, and the two-part
// layout. The text column is built here from OnboardingComponents; the picture beside it comes
// from OnboardingStage.

import AVFoundation
import SwiftUI

/// What the dashboard step offers. Choosing `homeAssistant` adds the Home Assistant link step.
enum OnboardingDashboardChoice {
    case homeAssistant, homeAssistantDemo, website
}

// MARK: - OnboardingView

struct OnboardingView: View {
    var onComplete: () -> Void
    /// `true` when launched from Settings → Setup assistant rather than on a first run. A re-run
    /// starts from the configuration that already exists instead of demanding every choice again,
    /// and can be left without walking to the end.
    var isRerun: Bool = false

    private enum Step: Hashable {
        case welcome, presence, presenceTryOut, dashboard, idle, pin, homeAssistant, finish
    }

    /// Pre-filled by the Home Assistant card, and recognised on a re-run to restore that choice.
    private static let homeAssistantDefaultURL = "http://homeassistant.local:8123"

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var kioskManager: KioskManager
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var slideForward = true
    @State private var urlText = ""
    @State private var urlError: String? = nil
    @State private var dashboardChoice: OnboardingDashboardChoice? = nil
    @State private var selectedIdleType: IdleScreenType = .clock
    /// Only the face is picked here; its theme and options live in Settings › Idle Screen, so the
    /// first run stays one tap per question.
    @State private var selectedClockStyle: ClockStyle = .digital
    /// Idle screen URL, only collected when `selectedIdleType == .customURL`.
    @State private var idleURLText = ""
    @State private var idleURLError: String? = nil
    /// Shown when Photos is chosen without any photos. Photos are saved as they're picked.
    @State private var idlePhotosError: String? = nil
    @State private var showingPINSetup = false
    /// Set by `PINSetupView`'s completion callback, consumed when its sheet finishes dismissing.
    @State private var didSetPIN = false
    /// Read once when the flow appears, and again after a request resolves. Determines whether
    /// the presence step can still raise the system dialog or has to explain an existing decision.
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @StateObject private var tryOut = PresenceTryOutModel()

    // MARK: - Steps

    /// The steps this run walks through. Two are conditional, so the list is derived rather
    /// than counted: the live try-out needs the camera, and the Home Assistant link only makes
    /// sense for someone who has Home Assistant.
    private var steps: [Step] {
        var steps: [Step] = [.welcome, .presence]
        if offersTryOut { steps.append(.presenceTryOut) }
        steps += [.dashboard, .idle, .pin]
        if dashboardChoice == .homeAssistant { steps.append(.homeAssistant) }
        steps.append(.finish)
        return steps
    }

    /// First run only. On a re-run the real presence pipeline is already sampling, and two
    /// capture sessions would fight over the front camera.
    private var offersTryOut: Bool {
        !isRerun && cameraStatus == .authorized && settings.presenceMode == .automatic
    }

    /// The steps the progress pills count. Welcome is a cover page, and the try-out is the
    /// second half of the presence step rather than a step of its own.
    private var countedSteps: [Step] {
        steps.filter { $0 != .welcome && $0 != .presenceTryOut }
    }

    private var countedIndex: Int? {
        countedSteps.firstIndex(of: step == .presenceTryOut ? .presence : step)
    }

    // MARK: - Body

    var body: some View {
        // Chooses between side by side and stacked. Nothing in SwiftUI does this for a custom
        // two-part layout on iOS 15 (`ViewThatFits` is 16+), so the space is measured once here.
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height && geo.size.width >= 900

            Group {
                if isWide {
                    HStack(spacing: 28) {
                        textColumn
                            .frame(width: min(468, geo.size.width * 0.42))
                        stage(isCompact: false)
                    }
                } else {
                    VStack(spacing: 20) {
                        stage(isCompact: true)
                            .frame(height: geo.size.height * 0.4)
                        textColumn
                    }
                }
            }
            .padding(isWide ? 28 : 20)
        }
        .background(Color.black.ignoresSafeArea())
        // The flow is designed dark, like the idle screen and the kiosk it leads into.
        .environment(\.colorScheme, .dark)
        .tint(OnboardingPalette.orange)
        .sheet(isPresented: $showingPINSetup) {
            PINSetupView(savedPIN: $settings.exitPIN, onSet: { didSetPIN = true })
        }
        .onChangeCompat(of: showingPINSetup) { isShowing in
            // Advancing on dismissal rather than from the callback keeps the step transition
            // from animating underneath the sheet on its way out.
            if !isShowing && didSetPIN {
                didSetPIN = false
                advance(from: .pin)
            }
        }
        .onAppear {
            // A first run demands an explicit dashboard choice, so it starts empty. A re-run
            // starts from what is already configured - otherwise reaching any later step means
            // retyping the dashboard URL, or silently replacing it with the Home Assistant
            // default, because the dashboard step cannot be passed without picking a card.
            if isRerun, !settings.homeURL.trimmingCharacters(in: .whitespaces).isEmpty {
                urlText = settings.homeURL.trimmingCharacters(in: .whitespaces)
                switch urlText {
                case Self.homeAssistantDefaultURL:      dashboardChoice = .homeAssistant
                case AppSettings.homeAssistantDemoURL:  dashboardChoice = .homeAssistantDemo
                default:                                dashboardChoice = .website
                }
            } else {
                urlText = ""
                dashboardChoice = nil
            }
            urlError = nil
            selectedIdleType = settings.idleScreenType
            selectedClockStyle = settings.clockStyle
            idleURLText = settings.idleCustomURL
            idleURLError = nil
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    // MARK: - Text column

    private var textColumn: some View {
        VStack(spacing: 0) {
            topBar

            if step == .welcome {
                // Three lines read better centred than pinned to the top of a scroll view.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    stepContent
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }

            VStack(spacing: 14) {
                if let countedIndex {
                    ProgressPills(current: countedIndex, total: countedSteps.count)
                }
                footerButtons
            }
            .padding(.top, 12)
        }
        .padding(.leading, 12)
    }

    /// Back on every step but the first; Close only on a re-run, where the flow is not a gate
    /// to the app and walking every step just to get out would mean re-answering everything.
    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.leading, -12)
            }
            Spacer()
            if isRerun {
                // "Close", not "Cancel": each step applies its change as you pass it, so
                // leaving early keeps what was already set rather than undoing it.
                Button("Close") { dismiss() }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            } else if let eyebrow {
                OnboardingEyebrow(text: eyebrow)
            }
        }
        .frame(height: 44)
    }

    private var eyebrow: String? {
        switch step {
        case .welcome: nil
        case .presence: "Presence"
        case .presenceTryOut: "Live try-out"
        case .dashboard: "Dashboard"
        case .idle: "Idle screen"
        case .pin: "PIN lock"
        case .homeAssistant: "Home Assistant link"
        case .finish: "One last thing"
        }
    }

    // MARK: - Stage

    private func stage(isCompact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)

        return ZStack {
            // One gradient for the whole flow, so it keeps moving across step changes.
            AnimatedBlobGradient()
                .opacity(0.5)
            Color.black.opacity(0.25)

            stageContent(isCompact: isCompact)
                .id(step)
                .transition(.opacity)
                .padding(isCompact ? 20 : 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingPalette.stageBase)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func stageContent(isCompact: Bool) -> some View {
        switch step {
        case .welcome:
            WelcomeStage()
        case .presence:
            PresenceStage(isCompact: isCompact)
        case .presenceTryOut:
            PresenceTryOutStage(model: tryOut)
        case .dashboard:
            DashboardStage(choice: dashboardChoice, address: urlText)
        case .idle:
            IdleStage(type: selectedIdleType, clockStyle: selectedClockStyle)
        case .pin:
            PinStage()
        case .homeAssistant:
            HomeAssistantStage(
                isOn: settings.homeAssistantLinkEnabled,
                deviceName: settings.homeAssistantDeviceName.trimmingCharacters(in: .whitespaces),
                isCompact: isCompact
            )
        case .finish:
            FinishStage(corner: settings.settingsCorner, showsPullTab: settings.showBrowserDrawer)
        }
    }

    // MARK: - Footer buttons

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case .welcome:
            OnboardingButton(title: "Get started") { advance(from: .welcome) }
        case .presence:
            OnboardingButton(title: "Continue", action: continueFromPresenceStep)
        case .presenceTryOut:
            OnboardingButton(title: "Continue") { advance(from: .presenceTryOut) }
        case .dashboard:
            OnboardingButton(title: "Continue", action: validateAndAdvance)
                .disabled(dashboardChoice == nil)
        case .idle:
            OnboardingButton(title: "Continue", action: continueFromIdleStep)
        case .pin:
            HStack(spacing: 10) {
                OnboardingButton(title: "Skip for now", isProminent: false) { advance(from: .pin) }
                OnboardingButton(title: "Set a PIN") { showingPINSetup = true }
            }
        case .homeAssistant:
            HStack(spacing: 10) {
                if settings.homeAssistantLinkEnabled {
                    OnboardingButton(title: "Turn off", isProminent: false) { setHomeAssistantLink(false) }
                    OnboardingButton(title: "Continue") { advance(from: .homeAssistant) }
                } else {
                    OnboardingButton(title: "Skip for now", isProminent: false) { advance(from: .homeAssistant) }
                    OnboardingButton(title: "Turn on the link") { setHomeAssistantLink(true) }
                }
            }
        case .finish:
            OnboardingButton(title: "All done, open my display", action: complete)
        }
    }

    // MARK: - Navigation

    private func advance() {
        let steps = steps
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            slideForward = true
            step = steps[index + 1]
        }
    }

    /// Footer-button entry point. A step transition takes 0.35 s to render, and on the slower
    /// iPads this app supports a second tap can land before the footer has swapped to the next
    /// step's button - advancing twice and skipping a step. Passing the step the button was drawn
    /// for makes the stale tap a no-op.
    private func advance(from expectedStep: Step) {
        guard step == expectedStep else { return }
        advance()
    }

    private func goBack() {
        let steps = steps
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            slideForward = false
            step = steps[index - 1]
        }
    }

    private func complete() {
        // This cover first: on a re-run `onComplete` closes the settings sheet that presents it,
        // and tearing the presenter down while this is still dismissing can strand the
        // presentation.
        dismiss()
        onComplete()
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// The presence step's primary action. `requestAccess` only raises the system dialog while
    /// the status is `.notDetermined`; in every other state it returns the standing decision
    /// immediately, so calling it unconditionally would make this step look inert. Each state is
    /// handled instead.
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
                    advance(from: .presence)
                }
            }
        case .denied, .restricted:
            // The step already explains this (see `presenceStatusNote`), so just move on.
            fallBackIfCameraModeUnusable()
            advance(from: .presence)
        default:
            // Already authorized: nothing to ask, and the mode is whatever the user chose.
            advance(from: .presence)
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
        guard AppSettings.webURL(from: text) != nil else { return nil }
        return text.trimmingCharacters(in: .whitespaces)
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
        advance(from: .dashboard)
    }

    /// The Custom URL option is only committed once it has a URL to load - otherwise the mode is
    /// saved with an empty `idleCustomURL`, and `IdleView` quietly shows the clock while Settings
    /// reports Custom URL.
    private func continueFromIdleStep() {
        if selectedIdleType == .photos, settings.idlePhotos.isEmpty {
            idlePhotosError = "Add at least one photo, or choose another option."
            return
        }
        idlePhotosError = nil
        if selectedIdleType == .customURL {
            guard let url = normalizedURL(from: idleURLText) else {
                idleURLError = Self.urlErrorMessage
                return
            }
            idleURLError = nil
            settings.idleCustomURL = url
        }
        settings.idleScreenType = selectedIdleType
        if selectedIdleType == .clock {
            settings.clockStyle = selectedClockStyle
        }
        resignKeyboard()
        advance(from: .idle)
    }

    /// Only the setting changes here. On a first run `HomeAssistantLink` has not been started
    /// yet - `ContentView` starts it once this flow is gone - so the Local Network prompt
    /// cannot appear over the setup.
    private func setHomeAssistantLink(_ isOn: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            settings.homeAssistantLinkEnabled = isOn
        }
    }

    // MARK: - Step content (buttons are in the fixed footer, not here)

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .presence: presenceStep
        case .presenceTryOut: presenceTryOutStep
        case .dashboard: dashboardStep
        case .idle: idleScreenStep
        case .pin: pinStep
        case .homeAssistant: homeAssistantStep
        case .finish: finishStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeadline(plain: "Welcome to ", highlight: "DashPad.", size: 52)
            Text("Your iPad, turned into a dedicated, always-on dashboard display.")
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)
            bodyText("Let's set it up together. Everything can be changed later in Settings.")
        }
    }

    // MARK: - Presence detection

    private var presenceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeadline(plain: "Wakes when you ", highlight: "walk in.")
            bodyText("DashPad can use the front camera to detect when someone is nearby, showing your content when you're present and switching to an idle screen when you walk away.")

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    FactTile(text: "The camera fires for ~3 seconds per sample, then shuts off")
                    FactTile(text: "Frames are processed on-device and immediately discarded")
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    FactTile(text: "Nothing is recorded, stored, or sent anywhere")
                    FactTile(text: "The camera LED is visible every time it activates")
                }
                .fixedSize(horizontal: false, vertical: true)
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
                tint: OnboardingPalette.orange,
                text: "Camera access is already allowed, but presence detection is off because Presence Mode is set to \(settings.presenceMode.displayName). Choose Automatic in Settings → Presence to turn it on."
            )
        default:
            footerNote("Sample rate, timeout, and sensitivity are all configurable. If you decline, presence detection stays off. You can turn it on anytime in Settings → Presence.")
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
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// `.restricted` means camera use is blocked device-wide, which the app's own permission
    /// row in iOS Settings cannot fix - so the two states are worded differently.
    private var cameraUnavailableMessage: String {
        cameraStatus == .restricted
            ? "Camera use is switched off for this iPad by Screen Time or a device management profile. Presence detection will stay off and DashPad will keep the dashboard always on."
            : "Camera access for DashPad is currently off, so presence detection will stay off. You can allow it in iOS Settings → Privacy & Security → Camera, then pick Automatic in Settings → Presence."
    }

    // MARK: - Presence try-out

    private var presenceTryOutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeadline(plain: "Go on, ", highlight: "step away.")
            bodyText("The camera is on for this try-out. Step out of view and the dashboard rests. Come back and it wakes.")

            VStack(spacing: 10) {
                checklistRow(title: "Step out of view", detail: "The clock takes over", isDone: tryOut.hasSteppedAway)
                checklistRow(title: "Come back", detail: "The dashboard wakes", isDone: tryOut.hasComeBack)
            }

            footerNote("This is the only place DashPad ever shows the camera picture. In normal use each frame is checked on-device and immediately discarded.")
        }
    }

    private func checklistRow(title: String, detail: String, isDone: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "Not done yet")
    }

    // MARK: - Dashboard URL

    private var dashboardStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeadline(plain: "What would you like to ", highlight: "display?")
            bodyText("DashPad shows a web dashboard full screen, such as Home Assistant running at home. Choose what it should load.")

            // The demo comes first: without a server of your own, the other two lead to an address
            // that can't load.
            VStack(spacing: 10) {
                dashboardCard(
                    .homeAssistantDemo,
                    symbol: "play.rectangle",
                    title: "Just looking? Try the demo",
                    description: "No Home Assistant yet? Load the public Home Assistant demo to see how DashPad looks."
                )
                dashboardCard(
                    .homeAssistant,
                    symbol: "homekit",
                    title: "I have Home Assistant at home",
                    description: "Pre-fills the usual local address. Edit it if yours is different."
                )
                dashboardCard(
                    .website,
                    symbol: "globe",
                    title: "A website or custom URL",
                    description: "Enter any URL this iPad can reach."
                )
            }

            // The demo's address is fixed, so there is nothing to type.
            if dashboardChoice != nil && dashboardChoice != .homeAssistantDemo {
                urlField(text: $urlText, error: urlError, onSubmit: validateAndAdvance)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footerNote("You can change this, add favourites, and restrict which domains the kiosk can navigate to in Settings → Dashboard.")
        }
    }

    private func dashboardCard(
        _ choice: OnboardingDashboardChoice, symbol: String, title: String, description: String
    ) -> some View {
        OptionCard(
            symbol: symbol,
            symbolTint: choice == .website ? OnboardingPalette.yellow : OnboardingPalette.orange,
            title: title,
            description: description,
            isSelected: dashboardChoice == choice
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                dashboardChoice = choice
                switch choice {
                case .homeAssistant:     urlText = Self.homeAssistantDefaultURL
                case .homeAssistantDemo: urlText = AppSettings.homeAssistantDemoURL
                case .website:           urlText = ""
                }
                urlError = nil
            }
        }
    }

    private func urlField(text: Binding<String>, error: String?, onSubmit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("http://", text: text)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(onSubmit)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Idle screen

    private var idleScreenStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeadline(plain: "What shows when no one's ", highlight: "around?")

            HStack(spacing: 10) {
                idleTile(.clock) {
                    ClockFaceView(style: selectedClockStyle, date: ClockFaceView.sampleDate, appearance: settings.clockAppearance)
                }
                idleTile(.photos) { tileSymbol("photo.on.rectangle.angled") }
                idleTile(.blank) { Color.black }
                idleTile(.customURL) { tileSymbol("globe") }
            }

            bodyText(idleDescription)

            switch selectedIdleType {
            case .clock:
                // Wider than the column, so the row can scroll out to its edges.
                ClockStylePicker(selection: $selectedClockStyle,
                                 appearance: settings.clockAppearance,
                                 thumbnailWidth: 120,
                                 edgeInset: 12,
                                 selectionColor: OnboardingPalette.orange)
                    .padding(.horizontal, -12)
                    .transition(.opacity)
            case .photos:
                VStack(alignment: .leading, spacing: 6) {
                    IdlePhotoGrid(thumbnailSize: 72)
                    if let error = idlePhotosError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .transition(.opacity)
                .onChangeCompat(of: settings.idlePhotos.isEmpty) { isEmpty in
                    if !isEmpty { idlePhotosError = nil }
                }
            case .customURL:
                urlField(text: $idleURLText, error: idleURLError, onSubmit: continueFromIdleStep)
                    .transition(.opacity)
            case .blank:
                EmptyView()
            }

            footerNote(idleStepFooter)
        }
    }

    private func idleTile<Preview: View>(_ type: IdleScreenType, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        OptionTile(title: type.displayName, isSelected: selectedIdleType == type, action: {
            withAnimation(.easeInOut(duration: 0.2)) { selectedIdleType = type }
        }, preview: preview)
    }

    private func tileSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 22))
            .foregroundStyle(OnboardingPalette.orange)
    }

    private var idleDescription: String {
        switch selectedIdleType {
        case .clock: "Eight faces, from dark night-friendly ones to colourful ones, easy to read at a distance."
        case .photos: "Your own photos. Pick several and they play as a slideshow."
        case .blank: "Solid black screen for the lowest power draw."
        case .customURL: "Load a different page: a slideshow, weather, or anything you like."
        }
    }

    private var idleStepFooter: String {
        switch selectedIdleType {
        case .clock: "Colours, typeface and other options are in Settings → Idle Screen."
        case .photos: "Slideshow timing, shuffle and a clock overlay are in Settings → Idle Screen."
        default: "Changeable anytime in Settings → Idle Screen."
        }
    }

    // MARK: - PIN lock

    private var pinStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeadline(plain: "Keep Settings ", highlight: "yours.")
            bodyText("Without a PIN, anyone who knows the gesture can open Settings. If this iPad is in a shared or public space, a PIN is worth setting.")

            VStack(spacing: 10) {
                FactRow(marker: .symbol("key.fill"), text: "PIN is stored securely in the iOS Keychain")
                FactRow(marker: .symbol("faceid"), text: "If you forget it, Face ID or your device passcode can unlock it")
                FactRow(marker: .symbol("gearshape"), text: "Set or change the PIN anytime in Settings → Kiosk Lock")
            }

            footerNote("Skipping is perfectly fine for a private setup where you're the only user.")
        }
    }

    // MARK: - Home Assistant link

    private var homeAssistantStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeadline(plain: "Make this iPad a Home Assistant ", highlight: "device.")

            if settings.homeAssistantLinkEnabled {
                bodyText("The link is on. Three things finish it:")
                VStack(spacing: 10) {
                    FactRow(marker: .number(1), text: "Allow Local Network access when iPadOS asks.")
                    FactRow(marker: .number(2), text: "In Home Assistant, open Settings → Devices & services. This iPad appears under Discovered.")
                    FactRow(marker: .number(3), text: "Enter the encryption key from DashPad's Settings → Home Assistant.")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device name")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("DashPad", text: $settings.homeAssistantDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                }
            } else {
                bodyText("Since your dashboard is Home Assistant, the iPad can join it as a device with its own entities. Automations can read its presence sensor, and wake the dashboard, send it idle or show the night screen.")
                VStack(spacing: 10) {
                    FactRow(text: "Nothing to install in Home Assistant. It appears as an ESPHome device.")
                    FactRow(text: "The iPad listens; Home Assistant connects. DashPad holds no login or token.")
                    FactRow(text: "Encrypted with a key shown in Settings. Stays on your local network.")
                }
                footerNote("Off unless you turn it on. Changeable anytime in Settings → Home Assistant.")
            }
        }
    }

    // MARK: - Getting back to Settings

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeadline(plain: "Getting back to ", highlight: "Settings.")
            bodyText("Once DashPad is running, the interface disappears so nothing gets in the way. Here's how to get back:")

            VStack(spacing: 10) {
                FactRow(
                    marker: .symbol("hand.tap"),
                    title: "Triple-tap the \(settings.settingsCorner.inlineName) corner",
                    text: "Three quick taps opens the PIN prompt (if set), then takes you straight to Settings."
                )
                if settings.showBrowserDrawer {
                    FactRow(
                        marker: .symbol("sidebar.right"),
                        title: "Or pull the tab on the right edge",
                        text: "A small drawer slides out with Refresh, Home, zoom and Settings."
                    )
                }
                FactRow(
                    marker: .symbol("lock.open.fill"),
                    title: "Forgot your PIN?",
                    text: "Tap 'Forgot PIN?' on the lock screen, then Face ID or your device passcode will unlock it."
                )
            }

            footerNote("You can re-run this setup anytime from Settings → Setup assistant.")
        }
    }

    // MARK: - Shared text

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
        .environmentObject(AppSettings())
        .environmentObject(KioskManager())
}
