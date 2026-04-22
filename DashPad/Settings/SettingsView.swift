import Combine
import SwiftUI

// MARK: - Category

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case dashboard  = "Dashboard"
    case kioskLock  = "Kiosk Lock"
    case presence   = "Presence"
    case idleScreen = "Idle Screen"
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
//        .presentationBackground(.regularMaterial)
    }

    // MARK: - Detail router

    @ViewBuilder
    private func detailContent(for category: SettingsCategory, s: Bindable<AppSettings>) -> some View {
        switch category {
        case .dashboard:  dashboardDetail(s)
        case .kioskLock:  kioskLockDetail(s)
        case .presence:   presenceDetail(s)
        case .idleScreen: idleScreenDetail(s)
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
        }
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail: Kiosk Lock

    @ViewBuilder
    private func kioskLockDetail(_ s: Bindable<AppSettings>) -> some View {
        Form {
            Section {
                LabeledContent("Exit PIN") {
                    SecureField("4–6 digits", text: s.exitPIN)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section {
                Button("Enter Kiosk Mode") {
                    kioskManager.dismissSettings()
                    kioskManager.activateKioskMode()
                }
            } footer: {
                Text("Triple-tap the top-right corner to open the PIN prompt and exit kiosk mode.")
            }
        }
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Kiosk Lock")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail: Presence

    @ViewBuilder
    private func presenceDetail(_ s: Bindable<AppSettings>) -> some View {
        Form {
            Section {
                SliderRow(label: "Idle Timeout", value: s.idleTimeout, range: 10...300, step: 5, unit: "s")
                SliderRow(label: "Camera Sample Rate", value: s.cameraSampleRate, range: 1...10, step: 1, unit: "s")
                SliderRow(label: "Light Threshold", value: s.lightThreshold, range: 0...0.3, step: 0.01, unit: "%", displayMultiplier: 100)
            }
        }
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .navigationTitle("Presence")
        .navigationBarTitleDisplayMode(.inline)
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
