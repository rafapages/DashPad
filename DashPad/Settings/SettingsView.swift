import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) var settings
    @Environment(KioskManager.self) var kioskManager

    var body: some View {
        // @Bindable lets us derive $-bindings from the @Observable AppSettings
        @Bindable var s = settings

        NavigationStack {
            Form {
                dashboardSection(s)
                kioskLockSection(s)
                presenceSection(s)
                idleScreenSection(s)
                brightnessSection(s)
                injectionSection(s)
                closeSection
            }
            .navigationTitle("DashPad")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func dashboardSection(_ s: Bindable<AppSettings>) -> some View {
        Section("Dashboard") {
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
        }
    }

    @ViewBuilder
    private func kioskLockSection(_ s: Bindable<AppSettings>) -> some View {
        Section {
            LabeledContent("Exit PIN") {
                SecureField("4–6 digits", text: s.exitPIN)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Button("Enter Kiosk Mode") {
                kioskManager.dismissSettings()
                kioskManager.activateKioskMode()
            }
        } header: {
            Text("Kiosk Lock")
        } footer: {
            Text("Triple-tap the top-right corner to open the PIN prompt and exit kiosk mode.")
        }
    }

    @ViewBuilder
    private func presenceSection(_ s: Bindable<AppSettings>) -> some View {
        Section("Presence Detection") {
            SliderRow(
                label: "Idle Timeout",
                value: s.idleTimeout,
                range: 10...300,
                step: 5,
                unit: "s"
            )
            SliderRow(
                label: "Camera Sample Rate",
                value: s.cameraSampleRate,
                range: 1...10,
                step: 1,
                unit: "s"
            )
            SliderRow(
                label: "Light Threshold",
                value: s.lightThreshold,
                range: 0...0.3,
                step: 0.01,
                unit: "%",
                displayMultiplier: 100
            )
        }
    }

    @ViewBuilder
    private func idleScreenSection(_ s: Bindable<AppSettings>) -> some View {
        Section("Idle Screen") {
            Picker("Type", selection: s.idleScreenType) {
                ForEach(IdleScreenType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            if settings.idleScreenType == .clock {
                Picker("Clock Style", selection: s.clockStyle) {
                    ForEach(ClockStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            if settings.idleScreenType == .customURL {
                LabeledContent("Custom URL") {
                    TextField("http://", text: s.idleCustomURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func brightnessSection(_ s: Bindable<AppSettings>) -> some View {
        Section("Brightness") {
            SliderRow(label: "Active", value: s.activeBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
            SliderRow(label: "Idle", value: s.idleBrightness, range: 0...1, step: 0.05, unit: "%", displayMultiplier: 100)
        }
    }

    @ViewBuilder
    private func injectionSection(_ s: Bindable<AppSettings>) -> some View {
        Section {
            NavigationLink("Custom CSS") {
                CodeEditorView(title: "Custom CSS", text: s.customCSS)
            }
            NavigationLink("Custom JavaScript") {
                CodeEditorView(title: "Custom JavaScript", text: s.customJS)
            }
        } header: {
            Text("CSS / JS Injection")
        } footer: {
            Text("Injected at page load via WKUserScript. Changes take effect on next page load.")
        }
    }

    private var closeSection: some View {
        Section {
            Button("Close Settings") { kioskManager.dismissSettings() }
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reusable slider row

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

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(KioskManager())
}
