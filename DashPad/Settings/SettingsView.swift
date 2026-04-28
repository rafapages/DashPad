// SettingsView.swift — NavigationSplitView settings panel, accessed via the secret gesture.
// All user-facing configuration lives here. Persisted immediately to AppSettings on change.

import Combine
import SwiftUI

// MARK: - Category

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case dashboard  = "Dashboard"
    case idleScreen = "Idle Screen"
    case kioskLock  = "Kiosk Lock"
    case presence   = "Presence"
    case brightness = "Brightness"
    case injection  = "Injection"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .dashboard:  "house.fill"
        case .kioskLock:  "lock.shield.fill"
        case .presence:   "person.fill.viewfinder"
        case .idleScreen: "moon.fill"
        case .brightness: "sun.max.fill"
        case .injection:  "chevron.left.slash.chevron.right"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard:  .blue
        case .kioskLock:  .orange
        case .presence:   .purple
        case .idleScreen: .indigo
        case .brightness: .yellow
        case .injection:  .green
        }
    }
}

// MARK: - Tinted icon badge (iOS Settings style)

private struct CategoryIcon: View {
    let category: SettingsCategory

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(category.tint.gradient, in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(AppSettings.self) var settings
    @Environment(KioskManager.self) var kioskManager
    @State private var selectedCategory: SettingsCategory? = .dashboard
    @State private var showingAddFavourite = false
    @State private var newFavouriteURL = ""
    @State private var showingPINSetup = false
    @State private var debugModeEnabled = false
    @State private var debugViewModel = PresenceDebugViewModel()
    @State private var addWindowRequest: AddWindowRequest? = nil

    var body: some View {
        let s = Bindable(settings)

        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { cat in
                Label {
                    Text(cat.rawValue)
                } icon: {
                    CategoryIcon(category: cat)
                }
                .tag(cat)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("DashPad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        kioskManager.dismissSettings()
                    }
                }
            }
        } detail: {
            if let category = selectedCategory {
                detailContent(for: category, s: s)
            } else {
                ContentUnavailableView("Select a setting", systemImage: "gear")
            }
        }
        .containerBackground(.clear, for: .navigationSplitView)
        .presentationDetents([.medium, .large])
        .onDisappear {
            kioskManager.debugViewModel = nil
        }
    }

    // MARK: - Detail router

    @ViewBuilder
    private func detailContent(for category: SettingsCategory, s: Bindable<AppSettings>) -> some View {
        switch category {
        case .dashboard:  dashboardDetail(s)
        case .idleScreen: idleScreenDetail(s)
        case .kioskLock:  kioskLockDetail(s)
        case .presence:   presenceDetail(s)
        case .brightness: brightnessDetail(s)
        case .injection:  injectionDetail(s)
        }
    }

    // MARK: - Detail: Dashboard

    @ViewBuilder
    private func dashboardDetail(_ s: Bindable<AppSettings>) -> some View {
        Form {
            Section {
                LabeledContent("Home URL") {
                    TextField("http://homeassistant.local:8123", text: s.homeURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Allowed Domains") {
                    TextField("Leave empty to allow all", text: s.allowedDomains)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Separate multiple domains with commas, e.g. homeassistant.local, myserver.com")
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
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
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
    private func kioskLockDetail(_ s: Bindable<AppSettings>) -> some View {
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
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Kiosk Lock")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPINSetup) {
            PINSetupView(savedPIN: s.exitPIN)
        }
    }

    // MARK: - Detail: Presence

    @ViewBuilder
    private func presenceDetail(_ s: Bindable<AppSettings>) -> some View {
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

            switch settings.presenceMode {
            case .automatic:
                automaticPresenceControls(s)
            case .schedule:
                scheduleControls(s)
            case .alwaysActive:
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Presence")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: settings.presenceMode)
        .animation(.default, value: debugModeEnabled)
        .onChange(of: settings.presenceMode) { _, mode in
            if mode != .automatic { debugModeEnabled = false }
            kioskManager.setPresenceMode(mode)
        }
        .onChange(of: debugModeEnabled) { _, enabled in
            kioskManager.debugViewModel = enabled ? debugViewModel : nil
        }
        .sheet(item: $addWindowRequest) { request in
            NavigationStack {
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

    // MARK: - Automatic (camera) controls

    @ViewBuilder
    private func automaticPresenceControls(_ s: Bindable<AppSettings>) -> some View {
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
            Text("Body detects people by silhouette — works for side profiles and people facing away. Face requires a visible face and is less likely to trigger on background movement.")
        }
        Section {
            SliderRow(label: "Day Sample Rate", value: s.cameraSampleRate, range: 1...30, step: 1, unit: "s")
            SliderRow(label: "Night Sample Rate", value: s.nightSampleRate, range: 10...300, step: 5, unit: "s")
        } footer: {
            Text("How often the camera fires when the room is lit (day) vs dark (night). A single photo is taken each time — the camera is active for ~3 seconds per sample.")
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
    private func scheduleControls(_ s: Bindable<AppSettings>) -> some View {
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
    private func windowSection(dayIndex: Int, title: String, s: Bindable<AppSettings>) -> some View {
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
    private func idleScreenDetail(_ s: Bindable<AppSettings>) -> some View {
        Form {
            Section {
                IdleOptionRow(label: "Clock",
                              isSelected: settings.idleScreenType == .clock) {
                    settings.idleScreenType = .clock
                }
                if settings.idleScreenType == .clock {
                    Picker("Style", selection: s.clockStyle) {
                        ForEach(ClockStyle.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    ClockPreviewCard()
                }
            } footer: {
                Text("Displays a full-screen clock. Choose between a minimal digital readout or a traditional analog face.")
            }

            Section {
                IdleOptionRow(label: "Custom URL",
                              isSelected: settings.idleScreenType == .customURL) {
                    settings.idleScreenType = .customURL
                }
                if settings.idleScreenType == .customURL {
                    LabeledContent("URL") {
                        TextField("http://", text: s.idleCustomURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("Loads a web page when idle — useful for dashboards, photo frames, or other always-on displays.")
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
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Idle Screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail: Brightness

    @ViewBuilder
    private func brightnessDetail(_ s: Bindable<AppSettings>) -> some View {
        Form {
            Section {
                SliderRow(label: "Active", value: s.activeBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
                SliderRow(label: "Idle", value: s.idleBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
            }
        }
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Brightness")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail: Injection

    @ViewBuilder
    private func injectionDetail(_ s: Bindable<AppSettings>) -> some View {
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
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
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
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
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

// MARK: - Clock preview card

private struct ClockPreviewCard: View {
    @Environment(AppSettings.self) var settings
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
            switch settings.clockStyle {
            case .digital:
                VStack(spacing: 6) {
                    Text(now, format: .dateTime.hour().minute().second())
                        .font(.system(size: 36, weight: .thin))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(now, format: .dateTime.weekday(.wide).month().day().year())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            case .analog:
                MiniAnalogClockFace(now: now)
            }
        }
        .frame(height: 130)
        .onReceive(ticker) { now = $0 }
    }
}

private struct MiniAnalogClockFace: View {
    let now: Date

    private var calendar: Calendar { .current }
    private var seconds: Double { Double(calendar.component(.second, from: now)) }
    private var minutes: Double { Double(calendar.component(.minute, from: now)) + seconds / 60 }
    private var hours: Double {
        Double(calendar.component(.hour, from: now)).truncatingRemainder(dividingBy: 12) + minutes / 60
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                .frame(width: 90, height: 90)
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -40)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            miniHand(angle: .degrees(hours * 30), length: 25, width: 3, color: .white)
            miniHand(angle: .degrees(minutes * 6), length: 35, width: 2, color: .white)
            miniHand(angle: .degrees(seconds * 6), length: 38, width: 1, color: .red)
            Circle().fill(Color.white).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private func miniHand(angle: Angle, length: CGFloat, width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(angle)
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
            .environment(AppSettings())
            .environment(km)
    }
}
