// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// OnboardingStage.swift - the picture side of the setup flow. Each step has a stage that shows
// what the step is about on a small iPad, using the app's real views wherever one exists.

import AVFoundation
import SwiftUI

// MARK: - Building blocks

/// A small iPad in landscape. Its screen has the clock faces' design proportions, so a real
/// `ClockFaceView` fills it exactly.
struct DeviceFrame<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var bezel: CGFloat = 11
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.black
            .aspectRatio(ClockDesign.aspectRatio, contentMode: .fit)
            .overlay(content())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - bezel, style: .continuous))
            .padding(bezel)
            .background(Color(hex: "#0C0C0E"), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color(hex: "#26272B"))
                    .frame(width: 5, height: 5)
                    .padding(.top, (bezel - 5) / 2)
            }
            .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 24)
            .accessibilityHidden(true)
    }
}

/// A stand-in dashboard: nine tiles, two of them in the brand colours.
struct MiniDashboard: View {
    private let columns: [CGFloat] = [1, 1, 2.1]
    private let rows: [CGFloat] = [0.55, 1, 1]

    var body: some View {
        // Proportional tiles need the size; this is not an orientation switch.
        GeometryReader { geo in
            let pad = geo.size.width * 0.05
            let gap = geo.size.width * 0.035
            let widths = lengths(columns, total: geo.size.width - 2 * pad - 2 * gap)
            let heights = lengths(rows, total: geo.size.height - 2 * pad - 2 * gap)

            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { column in
                            RoundedRectangle(cornerRadius: geo.size.width * 0.025, style: .continuous)
                                .fill(fill(row * 3 + column))
                                .frame(width: widths[column], height: heights[row])
                        }
                    }
                }
            }
            .padding(pad)
        }
        .background(
            RadialGradient(
                colors: [Color(hex: "#23262A"), Color(hex: "#0B0B0D")],
                center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 500
            )
        )
    }

    private func lengths(_ weights: [CGFloat], total: CGFloat) -> [CGFloat] {
        let sum = weights.reduce(0, +)
        return weights.map { max(0, total * $0 / sum) }
    }

    private func fill(_ index: Int) -> AnyShapeStyle {
        switch index {
        case 3: AnyShapeStyle(LinearGradient(
            colors: [OnboardingPalette.orange, OnboardingPalette.pink], startPoint: .leading, endPoint: .trailing
        ))
        case 7: AnyShapeStyle(OnboardingPalette.yellow)
        default: AnyShapeStyle(Color.white.opacity(0.12))
        }
    }
}

/// A stand-in web page, for "any website" and the Custom URL idle screen.
struct MiniWebPage: View {
    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.height / 20
            VStack(alignment: .leading, spacing: unit) {
                RoundedRectangle(cornerRadius: unit * 0.8, style: .continuous)
                    .fill(OnboardingPalette.gradient)
                    .frame(height: unit * 7)
                Capsule().fill(Color(hex: "#1A1A1A")).frame(width: geo.size.width * 0.55, height: unit * 1.3)
                Capsule().fill(Color(hex: "#1A1A1A").opacity(0.3)).frame(width: geo.size.width * 0.78, height: unit * 0.8)
                Capsule().fill(Color(hex: "#1A1A1A").opacity(0.3)).frame(width: geo.size.width * 0.66, height: unit * 0.8)
                Spacer(minLength: 0)
            }
            .padding(unit * 1.2)
        }
        .background(Color(hex: "#F2EFE8"))
    }
}

/// A rounded label that floats over the stage.
struct StagePill<Leading: View>: View {
    let text: String
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 9) {
            leading()
            Text(text).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension StagePill where Leading == StatusDot {
    init(_ text: String, dot: Color) {
        self.init(text: text) { StatusDot(color: dot) }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

private struct StageCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Welcome

/// The whole idea in one loop: the room empties and the iPad rests, someone arrives and it wakes.
struct WelcomeStage: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAwake = false

    var body: some View {
        VStack(spacing: 28) {
            DeviceFrame {
                ZStack {
                    ClockFaceView(style: .digital, date: ClockFaceView.sampleDate, appearance: settings.clockAppearance)
                    if isAwake {
                        MiniDashboard().transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: 520)

            if isAwake {
                StagePill("Someone's here. Awake.", dot: .green)
            } else {
                StagePill("Room empty. Resting.", dot: .gray)
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation(.easeInOut(duration: 0.8)) { isAwake.toggle() }
            }
        }
    }
}

// MARK: - Presence

struct PresenceStage: View {
    /// Portrait: less room, so the explanation strip is dropped.
    let isCompact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let videoURL = Bundle.main.url(forResource: "dashpad_v2", withExtension: "mov")
    private static let steps = ["A quick glance", "On-device check", "Show or rest", "The frame is gone"]

    var body: some View {
        VStack(spacing: 24) {
            Group {
                if let url = Self.videoURL {
                    Color.black
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay(LoopingVideoView(url: url, autoplays: !reduceMotion))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 24)
                        .accessibilityLabel("Video: the dashboard waking as someone walks up to the iPad")
                } else {
                    DeviceFrame { MiniDashboard() }.frame(maxWidth: 520)
                }
            }

            if !isCompact {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(OnboardingPalette.orange)
                            Text(step)
                                .font(.footnote.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

// MARK: - Presence try-out

struct PresenceTryOutStage: View {
    @ObservedObject var model: PresenceTryOutModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 20) {
            preview
            HStack(spacing: 20) {
                DeviceFrame(cornerRadius: 18, bezel: 7) {
                    ZStack {
                        ClockFaceView(style: .digital, date: ClockFaceView.sampleDate, appearance: settings.clockAppearance)
                        if model.personPresent {
                            MiniDashboard().transition(.opacity)
                        }
                    }
                }
                .frame(width: 210)

                VStack(alignment: .leading, spacing: 5) {
                    OnboardingEyebrow(text: "Your iPad right now")
                    Text(model.personPresent ? "Awake" : "Resting")
                        .font(.title2.weight(.bold))
                    Text(model.personPresent
                         ? "Showing your dashboard while you are here."
                         : "Showing the idle screen until someone comes back.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            model.start(detectionMode: settings.detectionMode, darkLuminanceThreshold: settings.darkLuminanceThreshold)
        }
        .onDisappear { model.stop() }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let isLive = model.cameraState == .running

        return ZStack {
            Color(hex: "#1D2023")
            if model.cameraState == .unavailable {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 34))
                    Text("The camera isn't available right now. You can carry on, and presence detection will start once setup is finished.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(28)
            } else {
                CameraPreview(camera: model.camera, isRunning: isLive)
                    .accessibilityLabel("Live front camera preview")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                isLive && model.personPresent ? Color.green : Color.white.opacity(0.12),
                lineWidth: isLive && model.personPresent ? 3 : 1
            )
        )
        .overlay(alignment: .top) {
            if isLive {
                Group {
                    if model.personPresent {
                        Text("Person detected")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(hex: "#04210C"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.green, in: Capsule())
                    } else {
                        StagePill("No one in view", dot: .gray)
                    }
                }
                .padding(.top, 16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isLive {
                StagePill(model.isRoomDark ? "Room light: dark" : "Room light: bright",
                          dot: model.isRoomDark ? .indigo : .yellow)
                    .padding(14)
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardStage: View {
    let choice: OnboardingDashboardChoice?
    let address: String

    var body: some View {
        VStack(spacing: 24) {
            StagePill(text: displayAddress) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            .font(.system(.subheadline, design: .monospaced))

            DeviceFrame {
                switch choice {
                case .website: MiniWebPage()
                default: MiniDashboard()
                }
            }
            .frame(maxWidth: 520)

            Group {
                switch choice {
                case .homeAssistant:
                    StagePill(text: "Adds one step later: make this iPad a Home Assistant device") { BrandDot() }
                case .homeAssistantDemo:
                    StageCaption(text: "A public demo. Nothing to set up, nothing to type.")
                case .website:
                    StageCaption(text: "Any page, full screen, with no browser chrome.")
                case nil:
                    StageCaption(text: "Pick one to see it here.")
                }
            }
            .frame(minHeight: 44)
        }
    }

    /// The address without its scheme, as a browser would show it.
    private var displayAddress: String {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let host = url.host else {
            return choice == nil ? "your dashboard" : "your address"
        }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

// MARK: - Idle screen

struct IdleStage: View {
    let type: IdleScreenType
    let clockStyle: ClockStyle
    @EnvironmentObject private var settings: AppSettings
    @State private var photo: UIImage?

    var body: some View {
        VStack(spacing: 24) {
            DeviceFrame {
                switch type {
                case .clock:
                    ClockFaceView(style: clockStyle, date: ClockFaceView.sampleDate, appearance: settings.clockAppearance)
                        .id(clockStyle)
                        .transition(.opacity)
                case .photos:
                    photoPreview
                case .blank:
                    Color.black
                case .customURL:
                    MiniWebPage()
                }
            }
            .frame(maxWidth: 520)
            .animation(.easeInOut(duration: 0.25), value: clockStyle)

            VStack(spacing: 6) {
                Text(type == .clock ? clockStyle.displayName : type.displayName)
                    .font(.title2.weight(.bold))
                StageCaption(text: caption)
            }
        }
        // Decoding a full-size photo on the main thread would stall the step transition.
        .task(id: settings.idlePhotos.first) {
            guard let first = settings.idlePhotos.first else {
                photo = nil
                return
            }
            photo = await Task.detached(priority: .userInitiated) {
                IdlePhotoStore.prepareSlide(first, withBackdrop: false)?.image
            }.value
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let photo {
            Color.black.overlay(
                Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill)
            )
            .clipped()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .light))
                Text("Your photos will play here")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        switch type {
        case .clock: clockStyle.isClassic ? "Mostly black, so it gives off the least light at night." : "Drawn live. Colours and typeface are yours to change later."
        case .photos: "Your picks, playing as a slideshow."
        case .blank: "Nothing lit. The lowest power draw."
        case .customURL: "Any page you like, while the room is empty."
        }
    }
}

// MARK: - PIN

struct PinStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = 0

    var body: some View {
        VStack(spacing: 24) {
            DeviceFrame {
                ZStack {
                    MiniDashboard().blur(radius: 6).opacity(0.7)
                    Color.black.opacity(0.5)
                    VStack(spacing: 14) {
                        Text("Enter PIN").font(.headline)
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.5)
                                    .background(Circle().fill(index < filled ? Color.white : .clear))
                                    .frame(width: 13, height: 13)
                            }
                        }
                        keypad
                    }
                }
            }
            .frame(maxWidth: 520)

            StageCaption(text: "What anyone sees before Settings opens.")
        }
        .task {
            guard !reduceMotion else {
                filled = 2
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeOut(duration: 0.15)) { filled = filled == 4 ? 0 : filled + 1 }
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 8) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]], id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { digit in
                        Text("\(digit)")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                }
            }
        }
    }
}

// MARK: - Home Assistant link

struct HomeAssistantStage: View {
    let isOn: Bool
    let deviceName: String
    /// Portrait: only the device card fits.
    let isCompact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            if !isCompact { connection }
            deviceCard
            if !isCompact { ideas }
        }
        .frame(maxWidth: 560)
    }

    private var connection: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                DeviceFrame(cornerRadius: 14, bezel: 5) { MiniDashboard() }
                    .frame(width: 150)
                Text("This iPad").font(.footnote.weight(.semibold))
            }

            VStack(spacing: 10) {
                OnboardingEyebrow(text: isOn ? "Encrypted · Local network" : "Not linked")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HorizontalLine()
                    .stroke(
                        isOn ? OnboardingPalette.orange : Color.gray.opacity(0.6),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 14], dashPhase: dashPhase)
                    )
                    .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(hex: "#04222E"))
                    .frame(width: 104, height: 104)
                    .background(Color(hex: "#18BCF2"), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
                Text("Home Assistant").font(.footnote.weight(.semibold))
            }
        }
        .onChangeCompat(of: isOn) { on in animateFlow(on) }
        .onAppear { animateFlow(isOn) }
    }

    /// Dashes travel from the iPad towards Home Assistant while the link is on.
    private func animateFlow(_ on: Bool) {
        guard on, !reduceMotion else {
            withAnimation(.default) { dashPhase = 0 }
            return
        }
        dashPhase = 0
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { dashPhase = -26 }
    }

    private var deviceCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(deviceName.isEmpty ? "DashPad" : deviceName).font(.headline)
                    Text("ESPHome · DashPad").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text(isOn ? "Ready to discover" : "Preview")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            entityRow("Presence") {
                HStack(spacing: 8) {
                    StatusDot(color: .green)
                    Text("Detected").fontWeight(.semibold)
                }
            }
            entityRow("Display") {
                Text("dashboard").font(.system(.footnote, design: .monospaced))
            }
            entityRow("Mode") {
                HStack(spacing: 2) {
                    ForEach(["Auto", "Dashboard", "Idle", "Night"], id: \.self) { mode in
                        Text(mode)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mode == "Auto" ? OnboardingPalette.ink : Color.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                mode == "Auto" ? OnboardingPalette.orange : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            entityRow("Room Brightness · Battery · Charging") {
                Text("Sensors").font(.footnote).foregroundStyle(.secondary)
            }
            entityRow("Reload Dashboard") {
                Text("Press")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.3), in: Capsule())
            }
        }
        .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 24)
        .opacity(isOn ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of this iPad as a device in Home Assistant, with presence, display, mode, sensors and a reload button")
    }

    private func entityRow<Value: View>(_ name: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(name)
                Spacer(minLength: 12)
                value()
            }
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private var ideas: some View {
        HStack(alignment: .top, spacing: 12) {
            idea("Bedroom lights go off → the iPad shows its night screen")
            idea("Doorbell rings → the doorbell camera shows for 30 seconds")
        }
        // Equal heights, but no taller than the longer of the two.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func idea(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OnboardingEyebrow(text: "Automation idea")
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Getting back to Settings

struct FinishStage: View {
    let corner: SettingsCorner
    let showsPullTab: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRippling = false
    @State private var isDrawerOpen = false

    var body: some View {
        VStack(spacing: 26) {
            DeviceFrame {
                MiniDashboard()
                    .overlay(alignment: corner.stageAlignment) { ripple.offset(corner.rippleOffset) }
                    .overlay(alignment: corner.stageAlignment) {
                        StagePill(text: "Tap, tap, tap") { EmptyView() }
                            .padding(corner.isLeading ? .leading : .trailing, 78)
                            .padding(corner.isTop ? .top : .bottom, 16)
                    }
                    .overlay(alignment: .trailing) {
                        if showsPullTab { drawer }
                    }
            }
            .frame(maxWidth: 520)

            StageCaption(text: showsPullTab
                         ? "Two ways back: three quick taps in the corner, or the tab on the right edge."
                         : "Invisible on your dashboard. Three quick taps in this corner.")
        }
        .onAppear {
            guard !reduceMotion else {
                isDrawerOpen = true
                return
            }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { isRippling = true }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isDrawerOpen.toggle() }
            }
        }
    }

    private var ripple: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .scaleEffect(isRippling ? 1.5 : 0.35)
                    .opacity(isRippling ? 0 : 0.95)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(ring) * 0.3),
                        value: isRippling
                    )
            }
            Circle()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        }
        .frame(width: 100, height: 100)
    }

    /// A sketch of `BrowserDrawer`: the handle that peeks out, and the panel behind it.
    private var drawer: some View {
        let panelWidth: CGFloat = 44
        let symbols = ["arrow.clockwise", "house", "plus.magnifyingglass", "minus.magnifyingglass", "gear"]

        return HStack(spacing: 0) {
            Image(systemName: "chevron.left")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isDrawerOpen ? 180 : 0))
                .frame(width: 11, height: 50)
                .background(Color(hex: "#3C3C42"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(spacing: 0) {
                ForEach(symbols, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(symbol == "gear" ? OnboardingPalette.orange : Color.white)
                        .frame(width: panelWidth, height: 38)
                    if symbol != symbols.last {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: panelWidth, height: 1)
                    }
                }
            }
            .background(
                Color(hex: "#3C3C42"),
                in: UnevenRoundedRectangleCompat(
                    topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 0, topTrailingRadius: 0
                )
            )
        }
        .shadow(color: .black.opacity(0.4), radius: 12, x: -4, y: 0)
        .offset(x: isDrawerOpen ? 0 : panelWidth)
    }
}

private extension SettingsCorner {
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeading: Bool { self == .topLeft || self == .bottomLeft }

    var stageAlignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    /// Pushes the ripple into the corner, so its centre sits where the taps go.
    var rippleOffset: CGSize {
        CGSize(width: isLeading ? -12 : 12, height: isTop ? -12 : 12)
    }
}
