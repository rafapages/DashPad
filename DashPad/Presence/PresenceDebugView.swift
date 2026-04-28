// PresenceDebugView.swift — developer debug overlay for the Automatic (camera) presence mode.
// Embedded inside the Presence settings section when Debug Mode is toggled on.
// Displays the last captured frame with Vision bounding boxes, live status rows, and an event log.

import Combine
import SwiftUI
import Vision

// MARK: - Debug sections (dropped into presenceDetail's Form)

struct PresenceDebugSections: View {
    @Environment(AppSettings.self) private var settings
    @Environment(KioskManager.self) private var km
    @Bindable var viewModel: PresenceDebugViewModel

    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            PhotoDebugCard(
                image: viewModel.lastPhoto,
                observations: viewModel.observations
            )
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .listRowInsets(EdgeInsets())
        }

        Section("Status") {
            statusRow("State", value: stateName)
            luminanceRow
            statusRow("Dark Threshold", value: String(format: "%.0f", settings.darkLuminanceThreshold))
            statusRow("Last Sample", value: lastSampleText)
            statusRow("Detected", value: "\(viewModel.observations.count)")
            statusRow("Timer", value: timerText)
        }

        Section {
            EventLogContent(viewModel: viewModel)
        } header: {
            HStack {
                Text("Event Log")
                Spacer()
                Button("Clear") { viewModel.clearLog() }
                    .font(.caption)
                    .textCase(nil)
            }
            .textCase(nil)
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Computed status values

    private var stateName: String {
        switch km.presenceState {
        case .idle:         return "Idle"
        case .sampling:     return "Sampling"
        case .active:       return "Active"
        case .rechecking:   return "Rechecking"
        case .countingDown: return "Counting Down"
        }
    }

    private var lastSampleText: String {
        guard viewModel.lastSampleDate != .distantPast else { return "—" }
        let age = now.timeIntervalSince(viewModel.lastSampleDate)
        return String(format: "%.1fs ago", max(0, age))
    }

    private var timerText: String {
        guard let start = km.stateTimerStartDate else { return "—" }
        let elapsed = now.timeIntervalSince(start)
        switch km.presenceState {
        case .active:
            return String(format: "%.0fs / %.0fs (recheck)", elapsed, settings.presenceRecheckInterval)
        case .countingDown:
            return String(format: "%.0fs / %.0fs (countdown)", elapsed, settings.idleTimeout)
        default:
            return "—"
        }
    }

    // MARK: - Row builders

    @ViewBuilder
    private var luminanceRow: some View {
        HStack {
            Text("Luminance")
            Spacer()
            HStack(spacing: 8) {
                let isDark = viewModel.lastLuminance < settings.darkLuminanceThreshold
                Text(String(format: "%.0f", viewModel.lastLuminance))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isDark ? .red : .green)
                LuminanceBar(level: viewModel.lastLuminance, threshold: settings.darkLuminanceThreshold)
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Static photo debug card

private struct PhotoDebugCard: View {
    let image: UIImage?
    let observations: [VNDetectedObjectObservation]

    var body: some View {
        ZStack {
            Color.black
            if let image {
                GeometryReader { geo in
                    let imageRect = fittedRect(imageSize: image.size, in: geo.size)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: .topLeading) {
                            Canvas { context, size in
                                for obs in observations {
                                    let box = obs.boundingBox
                                    // Vision uses bottom-left origin; flip Y for UIKit.
                                    let rect = CGRect(
                                        x: imageRect.minX + box.minX * imageRect.width,
                                        y: imageRect.minY + (1 - box.maxY) * imageRect.height,
                                        width: box.width * imageRect.width,
                                        height: box.height * imageRect.height
                                    )
                                    context.stroke(Path(rect), with: .color(.green), lineWidth: 2)

                                    let label = Text(String(format: "%.2f", obs.confidence))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.green)
                                    let labelRect = CGRect(
                                        x: rect.minX,
                                        y: max(2, rect.minY - 18),
                                        width: 44, height: 16
                                    )
                                    context.fill(
                                        Path(labelRect.insetBy(dx: -2, dy: -1)),
                                        with: .color(.black.opacity(0.65))
                                    )
                                    context.draw(label, in: labelRect)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                }
            } else {
                Text("No photo yet — waiting for first sample")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Returns the rect that `.scaledToFit` would occupy inside `containerSize`.
    private func fittedRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let h = containerSize.width / imageAspect
            return CGRect(x: 0, y: (containerSize.height - h) / 2,
                          width: containerSize.width, height: h)
        } else {
            let w = containerSize.height * imageAspect
            return CGRect(x: (containerSize.width - w) / 2, y: 0,
                          width: w, height: containerSize.height)
        }
    }
}

// MARK: - Luminance bar

private struct LuminanceBar: View {
    let level: Double
    let threshold: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.25))
                RoundedRectangle(cornerRadius: 2)
                    .fill(level >= threshold ? Color.green : Color.red)
                    .frame(width: geo.size.width * min(level / 255, 1.0))
            }
        }
        .frame(width: 48, height: 6)
    }
}

// MARK: - Event log content

private struct EventLogContent: View {
    @Bindable var viewModel: PresenceDebugViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.logEntries) { entry in
                            HStack(alignment: .top, spacing: 0) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.secondary)
                                Text("  \(entry.message)")
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("log-bottom")
                    }
                    .onChange(of: viewModel.logEntries.count) { _, _ in
                        withAnimation { proxy.scrollTo("log-bottom") }
                    }
                }
            }
            .frame(height: 180)

            Divider()

            Toggle("Verbose (capture events)", isOn: $viewModel.verboseFrameEvents)
                .font(.subheadline)
        }
    }
}
