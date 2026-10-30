// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// SettingsView.swift - NavigationSplitView settings panel, accessed via the secret gesture.
// All user-facing configuration lives here. Persisted immediately to AppSettings on change.

import AVFoundation
import Combine
import SwiftUI
import TipKit

// MARK: - Category

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case dashboard  = "Dashboard"
    case idleScreen = "Idle Screen"
    case kioskLock  = "Kiosk Lock"
    case presence   = "Presence"
    case brightness = "Brightness"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .dashboard:  "house.fill"
        case .kioskLock:  "lock.shield.fill"
        case .presence:   "person.fill.viewfinder"
        case .idleScreen: "moon.fill"
        case .brightness: "sun.max.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard:  .blue
        case .kioskLock:  .orange
        case .presence:   .purple
        case .idleScreen: .indigo
        case .brightness: .yellow
        }
    }
}

// MARK: - Tinted icon badge (iOS Settings style)

private struct SidebarIcon: View {
    let systemImage: String
    let tint: Color

    init(systemImage: String, tint: Color) {
        self.systemImage = systemImage
        self.tint = tint
    }

    init(category: SettingsCategory) {
        self.init(systemImage: category.systemImage, tint: category.tint)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint.gradientCompat, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Centers the icon against the whole title block. The default style aligns it to the
/// first line only, which leaves a two-line title (title + subtitle) hanging below the icon.
private struct CenteredIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - App Store review link

private enum AppStoreReview {
    /// The app's Apple ID from App Store Connect (App Information → General → Apple ID).
    /// While empty, the review row is hidden rather than linking to a page that doesn't exist.
    static let appID = "6766830819"

    /// Opens the App Store straight onto the write-a-review sheet. Used instead of
    /// `requestReview`, which the system rate-limits and may silently ignore - Apple advises
    /// against calling it from a button, since a tap that shows nothing looks broken.
    static var url: URL? {
        guard !appID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var kioskManager: KioskManager
    @Environment(\.openURL) private var openURL
    @State private var selectedCategory: SettingsCategory? = .dashboard
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showingAddFavourite = false
    @State private var newFavouriteURL = ""
    @State private var showingPINSetup = false
    @State private var debugModeEnabled = false
    @StateObject private var debugViewModel = PresenceDebugViewModel()
    @State private var addWindowRequest: AddWindowRequest? = nil
    @State private var showingSetupAssistant = false
    @State private var confirmingRemoveAllPhotos = false
    @AppStorage(WhatsNew.idleScreensTriedKey) private var idleScreensTried = false

    var body: some View {
        splitView
            .clearNavigationSplitViewBackground()
            .centredSheetSizing()
            .sheet(isPresented: $showingSetupAssistant) {
                OnboardingView(onComplete: {
                    kioskManager.dismissSettings()
                }, isRerun: true)
                .environmentObject(settings)
                .environmentObject(kioskManager)
            }
            .onDisappear {
                kioskManager.debugViewModel = nil
            }
    }

    /// `NavigationSplitView` is iOS 16+. iOS 15 gets the column-style `NavigationView` it
    /// replaced, where the sidebar drives the detail column through tagged navigation links
    /// because `List(selection:)` only selects in edit mode there.
    @ViewBuilder
    private var splitView: some View {
        let s = $settings

        if #available(iOS 16.0, *) {
            NavigationSplitView {
                sidebar {
                    List(selection: $selectedCategory) {
                        ForEach(SettingsCategory.allCases) { cat in
                            categoryLabel(cat)
                                .tag(cat)
                        }
                    }
                }
            } detail: {
                detailPane(s)
            }
        } else {
            NavigationView {
                sidebar {
                    List {
                        ForEach(SettingsCategory.allCases) { cat in
                            NavigationLink(tag: cat, selection: $selectedCategory) {
                                detailContent(for: cat, s: s)
                            } label: {
                                categoryLabel(cat)
                            }
                        }
                    }
                }
                detailPane(s)
            }
            .navigationViewStyle(.columns)
        }
    }

    private func categoryLabel(_ cat: SettingsCategory) -> some View {
        Label {
            Text(cat.rawValue)
        } icon: {
            SidebarIcon(category: cat)
        }
        .badge(showsNewBadge(cat) ? Text("New") : nil)
        .increasedBadgeProminence()
    }

    /// Flags a category that gained something since the user first set DashPad up, for a while
    /// after the update or until they try it.
    private func showsNewBadge(_ cat: SettingsCategory) -> Bool {
        cat == .idleScreen && !idleScreensTried && WhatsNew.idleScreensBadgeIsCurrent
    }

    @ViewBuilder
    private func detailPane(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        if let category = selectedCategory {
            detailContent(for: category, s: s)
        } else {
            EmptyStatePlaceholder(title: "Select a setting", systemImage: "gear")
        }
    }

    /// The category list with the sidebar's footer rows, title and Done button.
    private func sidebar<Content: View>(@ViewBuilder list: () -> Content) -> some View {
        list()
            .hiddenScrollContentBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let reviewURL = AppStoreReview.url {
                        sidebarFooterButton(action: { openURL(reviewURL) }) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Leave us a Review")
                                    Text("It really helps")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                SidebarIcon(systemImage: "star.fill", tint: .pink)
                            }
                        }
                    }
                    sidebarFooterButton(action: { showingSetupAssistant = true }) {
                        Label {
                            Text("Setup assistant")
                        } icon: {
                            SidebarIcon(systemImage: "wand.and.stars", tint: .secondary)
                        }
                    }
                    #if DEBUG
                    sidebarFooterButton(action: { WhatsNew.resetForTesting() }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset What's New")
                                Text("Debug builds only. Takes effect on relaunch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SidebarIcon(systemImage: "arrow.counterclockwise", tint: .secondary)
                        }
                    }
                    #endif
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("DashPad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        kioskManager.dismissSettings()
                    }
                }
            }
    }

    /// A row pinned below the sidebar list, inset to line up with the category rows above it.
    private func sidebarFooterButton<Content: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .labelStyle(CenteredIconLabelStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail router

    @ViewBuilder
    private func detailContent(for category: SettingsCategory, s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        switch category {
        case .dashboard:  dashboardDetail(s)
        case .idleScreen: idleScreenDetail(s)
        case .kioskLock:  kioskLockDetail(s)
        case .presence:   presenceDetail(s)
        case .brightness: brightnessDetail(s)
        }
    }

    // MARK: - Detail: Dashboard

    @ViewBuilder
    private func dashboardDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            Section {
                LabeledRow("Home URL") {
                    TextField("http://homeassistant.local:8123", text: s.homeURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
                LabeledRow("Allowed Domains") {
                    TextField("Leave empty to allow all", text: s.allowedDomains)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Separate multiple domains with commas, e.g. homeassistant.local, myserver.com")
            }

            Section {
                Toggle("Hide Status Bar", isOn: s.hideStatusBar)
            } footer: {
                Text("Hides the clock, date, battery and Wi-Fi indicators at the top of the screen. The status bar is always hidden on the idle screen.")
            }

            Section {
                Toggle("Prevent Auto-Lock", isOn: s.preventAutoLock)
            } footer: {
                Text("Keeps the device awake and unlocked while DashPad is open, even if Auto-Lock is turned on in the device's Settings. Turn off to let the device sleep as usual.")
            }

            Section {
                ForEach(settings.favouriteURLs, id: \.self) { url in
                    HStack {
                        Text(url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if settings.homeURL == url {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            settings.homeURL = url
                        } label: {
                            Label("Set as Home", systemImage: "house.fill")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            settings.favouriteURLs.removeAll { $0 == url }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button {
                    newFavouriteURL = ""
                    showingAddFavourite = true
                } label: {
                    Label("Add Favourite", systemImage: "plus")
                }
            } header: {
                Text("Favourites")
            } footer: {
                Text("Swipe right to set as Home URL. Swipe left to delete.")
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Add Favourite", isPresented: $showingAddFavourite) {
            TextField("https://", text: $newFavouriteURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Add") {
                let trimmed = newFavouriteURL.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !settings.favouriteURLs.contains(trimmed) else { return }
                settings.favouriteURLs.append(trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the URL to save as a favourite.")
        }
    }

    // MARK: - Detail: Kiosk Lock

    @ViewBuilder
    private func kioskLockDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            Section {
                Toggle("Require PIN", isOn: Binding(
                    get: { !settings.exitPIN.isEmpty },
                    set: { enabled in
                        if enabled {
                            showingPINSetup = true
                        } else {
                            settings.exitPIN = ""
                        }
                    }
                ))
                if !settings.exitPIN.isEmpty {
                    Button("Change PIN") {
                        showingPINSetup = true
                    }
                }
            } footer: {
                Text("When enabled, triple-tapping the bottom-right corner will ask for a PIN before opening Settings. Use Face ID or your device passcode if you forget it.")
            }
            Section {
                Button("Enter Kiosk Mode") {
                    kioskManager.dismissSettings()
                    kioskManager.activateKioskMode()
                }
            } footer: {
                Text("Locks the device to this app using Guided Access.")
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Kiosk Lock")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPINSetup) {
            PINSetupView(savedPIN: s.exitPIN)
        }
    }

    // MARK: - Detail: Presence

    @ViewBuilder
    private func presenceDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            Section {
                Picker("Presence Mode", selection: s.presenceMode) {
                    ForEach(PresenceMode.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                presenceModeFooter
            }

            // Outside the mode switch on purpose. Declining the camera leaves the mode on
            // Always Active, so a warning shown only under Automatic would be unreachable
            // by the very users who need it - there'd be no way back in.
            cameraAccessWarning

            switch settings.presenceMode {
            case .automatic:
                automaticPresenceControls(s)
            case .schedule:
                scheduleControls(s)
            case .alwaysActive:
                EmptyView()
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Presence")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: settings.presenceMode)
        .animation(.default, value: debugModeEnabled)
        .onChangeCompat(of: settings.presenceMode) { mode in
            if mode != .automatic { debugModeEnabled = false }
            kioskManager.setPresenceMode(mode)
        }
        .onChangeCompat(of: debugModeEnabled) { enabled in
            kioskManager.debugViewModel = enabled ? debugViewModel : nil
        }
        // Notification rather than `scenePhase`: this pane lives inside a sheet, where the
        // environment value's delivery has varied across the OS versions the app now supports.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .sheet(item: $addWindowRequest) { request in
            NavigationStackCompat {
                ScheduleWindowEditView(
                    initial: ScheduleWindow(startMinute: 480, endMinute: 1320),
                    allWindows: settings.weeklySchedule.windows[request.dayIndex],
                    title: "New Window"
                ) { newWindow in
                    settings.weeklySchedule.windows[request.dayIndex].append(newWindow)
                }
            }
        }
    }

    @ViewBuilder
    private var presenceModeFooter: some View {
        switch settings.presenceMode {
        case .automatic:
            Text("Uses the front camera to detect when someone is present.")
        case .schedule:
            Text("Active windows are defined by a fixed schedule. The camera is not used.")
        case .alwaysActive:
            Text("The dashboard stays on at all times. No detection is performed.")
        }
    }

    // MARK: - Camera access warning

    /// Shown in the Presence pane whenever the camera is unavailable, in any presence mode.
    /// `.restricted` is a device-wide block (Screen Time or a management profile) that the app's
    /// own permission row cannot lift, so it gets different wording and no dead-end button.
    @ViewBuilder
    private var cameraAccessWarning: some View {
        if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Camera access is off")
                        Text(cameraAuthorizationStatus == .restricted
                             ? "Camera use is switched off for this device by Screen Time or a device management profile, so Automatic mode can't detect anyone."
                             : "Automatic mode can't detect anyone until camera access is allowed for DashPad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if cameraAuthorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Automatic (camera) controls

    @ViewBuilder
    private func automaticPresenceControls(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Section {
            Toggle(isOn: $debugModeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Mode")
                    Text("Shows the last captured photo and pipeline events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if debugModeEnabled {
            PresenceDebugSections(viewModel: debugViewModel)
        }

        Section {
            Picker("Detection Mode", selection: s.detectionMode) {
                ForEach(DetectionMode.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
        } footer: {
            Text("Body detects people by silhouette, so it works for side profiles and people facing away. Face requires a visible face and is less likely to trigger on background movement.")
        }
        Section {
            SliderRow(label: "Day Sample Rate", value: s.cameraSampleRate, range: 1...30, step: 1, unit: "s")
            SliderRow(label: "Night Sample Rate", value: s.nightSampleRate, range: 10...300, step: 5, unit: "s")
        } footer: {
            Text("How often the camera fires when the room is lit (day) vs dark (night). A single photo is taken each time, and the camera is active for about 3 seconds per sample.")
        }
        Section {
            SliderRow(label: "Presence Recheck", value: s.presenceRecheckInterval, range: 5...120, step: 5, unit: "s")
        } footer: {
            Text("How long after detecting someone before the camera rechecks to confirm they are still there.")
        }
        Section {
            SliderRow(label: "Idle Timeout", value: s.idleTimeout, range: 10...300, step: 5, unit: "s")
        } footer: {
            Text("How long with no detection before the idle screen appears. During this countdown the camera continues sampling at the day rate.")
        }
        Section {
            SliderRow(label: "Dark Threshold", value: s.darkLuminanceThreshold, range: 0...80, step: 1, unit: "")
        } footer: {
            Text("Average frame luminance (0 – 255) below which the room is considered dark. Dark frames skip the detector and reschedule at the night rate.")
        }
    }

    // MARK: - Schedule controls

    @ViewBuilder
    private func scheduleControls(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Section {
            SliderRow(label: "Manual Wake Timeout", value: s.manualWakeTimeout, range: 30...600, step: 30, unit: "s")
        } footer: {
            Text("How long the dashboard stays visible after tapping the idle screen. Each tap resets the timer.")
        }

        Section {
            Toggle("Same Schedule Every Day", isOn: s.weeklySchedule.sameEveryDay)
        }

        if settings.weeklySchedule.sameEveryDay {
            windowSection(dayIndex: 0, title: "Active Windows", s: s)
        } else {
            let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            ForEach(0..<7, id: \.self) { dayIndex in
                windowSection(dayIndex: dayIndex, title: dayNames[dayIndex], s: s)
            }
        }
    }

    @ViewBuilder
    private func windowSection(dayIndex: Int, title: String, s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Section {
            let windows = settings.weeklySchedule.windows[dayIndex]
            ForEach(Array(windows.enumerated()), id: \.element.id) { idx, window in
                NavigationLink {
                    ScheduleWindowEditView(
                        initial: window,
                        allWindows: settings.weeklySchedule.windows[dayIndex],
                        title: "Edit Window"
                    ) { updated in
                        guard idx < settings.weeklySchedule.windows[dayIndex].count else { return }
                        settings.weeklySchedule.windows[dayIndex][idx] = updated
                    }
                } label: {
                    HStack {
                        Text(formattedMinute(window.startMinute))
                            .monospacedDigit()
                        Text("–")
                            .foregroundStyle(.secondary)
                        Text(formattedMinute(window.endMinute))
                            .monospacedDigit()
                        if window.spansMidnight {
                            Spacer()
                            Image(systemName: "moon.stars.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        settings.weeklySchedule.windows[dayIndex].remove(at: idx)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                addWindowRequest = AddWindowRequest(dayIndex: dayIndex)
            } label: {
                Label("Add Window", systemImage: "plus")
            }
            if !settings.weeklySchedule.windows[dayIndex].isEmpty {
                Button(role: .destructive) {
                    settings.weeklySchedule.windows[dayIndex].removeAll()
                } label: {
                    Label("Remove All Windows", systemImage: "trash")
                }
            }
        } header: {
            Text(title)
        }
    }

    // MARK: - Detail: Idle Screen

    @ViewBuilder
    private func idleScreenDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            IdleScreensTipSection()

            Section {
                IdleOptionRow(label: "Clock",
                              isSelected: settings.idleScreenType == .clock) {
                    settings.idleScreenType = .clock
                }
                if settings.idleScreenType == .clock {
                    ClockStylePicker(selection: s.clockStyle, appearance: settings.clockAppearance)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    ClockPreviewCard()
                    if settings.clockStyle.showsHourDigits {
                        menuPicker("Time format", selection: s.clockOptions.hourFormat, \.displayName)
                    }
                    if !settings.clockStyle.isClassic {
                        clockCustomisationRows(s)
                    }
                }
            } footer: {
                Text("Displays a full-screen clock. Pick a style, then make it yours with colours and a typeface.")
            }

            Section {
                IdleOptionRow(label: "Photos",
                              isSelected: settings.idleScreenType == .photos) {
                    settings.idleScreenType = .photos
                }
                if settings.idleScreenType == .photos {
                    IdlePhotoGrid()
                        .padding(.vertical, 6)
                    Toggle("Fill screen", isOn: s.photoOptions.fillScreen)
                    Toggle("Show clock", isOn: s.photoOptions.showClock)
                    // A single photo just stays up; the slideshow settings appear with a second.
                    if settings.idlePhotos.count > 1 {
                        menuPicker("Change every", selection: s.photoOptions.interval, \.displayName)
                        Toggle("Shuffle", isOn: s.photoOptions.shuffle)
                    }
                    if !settings.idlePhotos.isEmpty {
                        Button("Remove All Photos", role: .destructive) {
                            confirmingRemoveAllPhotos = true
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if settings.idleScreenType == .photos, settings.idlePhotos.isEmpty {
                        Label("Add at least one photo. Until then the clock is shown.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("Shows your photos when idle. Pick more than one and they play as a slideshow. Photos are copied into DashPad and stay on this device - DashPad never sees the rest of your library.")
                }
            }

            Section {
                IdleOptionRow(label: "Custom URL",
                              isSelected: settings.idleScreenType == .customURL) {
                    settings.idleScreenType = .customURL
                }
                if settings.idleScreenType == .customURL {
                    LabeledRow("URL") {
                        TextField("http://", text: s.idleCustomURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if settings.idleScreenType == .customURL, settings.idleWebURL == nil {
                        Label("Enter a full URL starting with http:// or https://. Until then the clock is shown.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("Loads a web page when idle - a Home Assistant view with a clock, weather or calendar, a photo frame, or any other always-on display. The page is display-only: tapping it wakes the dashboard.")
                }
            }

            Section {
                IdleOptionRow(label: "Blank",
                              isSelected: settings.idleScreenType == .blank) {
                    settings.idleScreenType = .blank
                }
            } footer: {
                Text("Solid black screen. Pair with a low idle brightness to minimise power use.")
            }
        }
        .animation(.default, value: settings.idleScreenType)
        .animation(.default, value: settings.clockStyle)
        .animation(.default, value: settings.idlePhotos.count > 1)
        .onChangeCompat(of: settings.clockStyle) { _ in invalidateIdleScreensTip() }
        .onChangeCompat(of: settings.idleScreenType) { type in
            if type == .photos { invalidateIdleScreensTip() }
        }
        .confirmationDialog("Remove all photos from the idle screen?",
                            isPresented: $confirmingRemoveAllPhotos,
                            titleVisibility: .visible) {
            Button("Remove All Photos", role: .destructive) {
                withAnimation { settings.removeAllIdlePhotos() }
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Idle Screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The user has found the new idle screens, so the tip and badge pointing at them have done their job.
    private func invalidateIdleScreensTip() {
        idleScreensTried = true
        if #available(iOS 17.0, *) {
            IdleScreensTip().invalidate(reason: .actionPerformed)
        }
    }

    /// Theme, typeface and the options that apply to the selected themed face. The classic
    /// faces are fixed black and white, so they get none of these.
    @ViewBuilder
    private func clockCustomisationRows(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        let options = s.clockOptions

        VStack(alignment: .leading, spacing: 10) {
            Text("Theme")
            ClockThemePicker(selection: themeBinding(for: settings.clockStyle), style: settings.clockStyle)
        }
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 10) {
            Text("Typeface")
            Picker("Typeface", selection: s.clockTypeface) {
                ForEach(ClockTypeface.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)

        Toggle("Show date", isOn: options.showDate)

        switch settings.clockStyle {
        case .numerals:
            Toggle("Seconds hand", isOn: options.showSeconds)
        case .tiles:
            menuPicker("Shape", selection: options.tileShape, \.displayName)
            Toggle("Split line", isOn: options.tileSplit)
        case .words:
            menuPicker("Language", selection: options.wordsLanguage, \.displayName)
            Toggle("Show time in digits", isOn: options.wordsShowDigits)
        case .halves:
            Toggle("Numbers bleed off edge", isOn: options.halvesBleed)
        case .sweep:
            menuPicker("Ring", selection: options.sweepRing, \.displayName)
            Toggle("Show minutes", isOn: options.sweepShowMinutes)
            Toggle("Hour marker", isOn: options.sweepShowHourDot)
        case .dots:
            menuPicker("Dot shape", selection: options.dotShape, \.displayName)
            Toggle("Row labels", isOn: options.dotsShowScale)
        case .digital, .analog:
            EmptyView()
        }
    }

    /// The selected face's own theme; changing it leaves every other face's theme alone.
    private func themeBinding(for style: ClockStyle) -> Binding<ClockTheme> {
        Binding(get: { settings.clockThemes[style] },
                set: { settings.clockThemes[style] = $0 })
    }

    private func menuPicker<Value: CaseIterable & Hashable>(
        _ title: String, selection: Binding<Value>, _ name: KeyPath<Value, String>
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Value.allCases, id: \.self) {
                Text($0[keyPath: name]).tag($0)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Detail: Brightness

    @ViewBuilder
    private func brightnessDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            Section {
                SliderRow(label: "Active", value: s.activeBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
                SliderRow(label: "Idle", value: s.idleBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Brightness")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail: Injection

    @ViewBuilder
    private func injectionDetail(_ s: EnvironmentObject<AppSettings>.Wrapper) -> some View {
        Form {
            Section {
                NavigationLink("Custom CSS") {
                    CodeEditorView(title: "Custom CSS", text: s.customCSS)
                }
                NavigationLink("Custom JavaScript") {
                    CodeEditorView(title: "Custom JavaScript", text: s.customJS)
                }
            } footer: {
                Text("Injected at page load via WKUserScript. Changes take effect on next page load.")
            }
        }
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .navigationTitle("Injection")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func formattedMinute(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

// MARK: - Add window request (carries the day index to the sheet)

private struct AddWindowRequest: Identifiable {
    let id = UUID()
    let dayIndex: Int
}

// MARK: - Schedule window edit view

private struct ScheduleWindowEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ScheduleWindow
    let allWindows: [ScheduleWindow]
    let title: String
    let onDone: (ScheduleWindow) -> Void

    init(initial: ScheduleWindow, allWindows: [ScheduleWindow], title: String = "Edit Window", onDone: @escaping (ScheduleWindow) -> Void) {
        _draft = State(initialValue: initial)
        self.allWindows = allWindows
        self.title = title
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
            }
            if draft.spansMidnight || hasOverlap {
                Section {
                    if draft.spansMidnight {
                        Label("This window spans midnight", systemImage: "moon.stars")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    if hasOverlap {
                        Label("Overlaps with another window", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .hiddenScrollContentBackground()
        .clearNavigationBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDone(draft)
                    dismiss()
                }
                .disabled(hasOverlap || !hasValidDuration)
            }
        }
    }

    private var hasOverlap: Bool {
        let others = allWindows.filter { $0.id != draft.id }
        return others.contains { minuteSet(draft).intersection(minuteSet($0)).isEmpty == false }
    }

    private var hasValidDuration: Bool { draft.startMinute != draft.endMinute }

    private var startBinding: Binding<Date> {
        Binding(
            get: { minuteToDate(draft.startMinute) },
            set: { draft.startMinute = dateToMinute($0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { minuteToDate(draft.endMinute) },
            set: { draft.endMinute = dateToMinute($0) }
        )
    }

    private func minuteToDate(_ minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = minute / 60
        components.minute = minute % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    private func dateToMinute(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func minuteSet(_ w: ScheduleWindow) -> Set<Int> {
        if w.spansMidnight {
            return Set(w.startMinute..<1440).union(Set(0..<w.endMinute))
        } else {
            return Set(w.startMinute..<w.endMinute)
        }
    }
}

// MARK: - Slider row

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var displayMultiplier: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(formattedValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }

    private var formattedValue: String {
        let v = value * displayMultiplier
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(v))\(unit)"
        }
        return String(format: "%.1f\(unit)", v)
    }
}

// MARK: - Code editor

private struct CodeEditorView: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 4)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Idle option row

private struct IdleOptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .imageScale(.large)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - What's new tip

/// `IdleScreensTip` as the first row of the Idle Screen form. TipKit is iOS 17+; earlier
/// releases get nothing here, and the sidebar badge alone points them at the new screens.
private struct IdleScreensTipSection: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            Section {
                TipView(IdleScreensTip())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }
}

// MARK: - Clock preview card

/// The selected face, live, drawn exactly as the idle screen draws it.
private struct ClockPreviewCard: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ClockFaceView(style: settings.clockStyle, date: context.date, appearance: settings.clockAppearance)
        }
        .aspectRatio(ClockDesign.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 4)
    }
}

#Preview {
    let km = KioskManager()
    km.showingSettings = true
    return ZStack {
        LinearGradient(colors: [.blue, .purple, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
    .sheet(isPresented: .constant(true)) {
        SettingsView()
            .environmentObject(AppSettings())
            .environmentObject(km)
    }
}
