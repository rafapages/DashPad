// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

import SwiftUI

struct BrowserDrawer: View {
    var webController: WebViewController

    @EnvironmentObject private var kioskManager: KioskManager
    @EnvironmentObject private var settings: AppSettings

    @State private var isOpen = false
    @State private var dragOffset: CGFloat = 0
    /// A finger is on the handle. Drives its pressed look, so a touch shows before anything moves.
    @State private var isHandlePressed = false
    @State private var dismissTask: Task<Void, Never>? = nil

    private let drawerWidth: CGFloat = 72
    private let snapThreshold: CGFloat = 40
    private let snapVelocityThreshold: CGFloat = 300
    /// A touch on the handle that moves less than this is a tap, which toggles the drawer.
    private let tapSlop: CGFloat = 8
    private let snap = Animation.spring(response: 0.35, dampingFraction: 0.82)

    var body: some View {
        ZStack(alignment: .trailing) {
            // Always full-screen so ZStack is always anchored to the trailing edge.
            // Tap dismisses the drawer only when open.
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if isOpen { close(animated: true) } }
                .allowsHitTesting(isOpen)

            // Always render handle + panel; offset moves them on/off screen.
            // ZStack trailing-aligns so x=0 → panel flush with right edge;
            // x=drawerWidth → only the 12pt handle peeks out.
            HStack(spacing: 0) {
                DrawerHandle(isOpen: isOpen, isPressed: isHandlePressed)
                    .gesture(handleGesture)

                DrawerPanel(
                    webController: webController,
                    onAction: { delayedClose in
                        resetDismissTimer()
                        if delayedClose { scheduleDelayedClose() }
                    }
                )
                // The open panel can be pushed back off the edge too. Simultaneous, and with a
                // minimum distance, so its buttons still take taps.
                .simultaneousGesture(panelGesture)
            }
            .offset(x: panelOffset)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }

    private var panelOffset: CGFloat {
        // x=0: fully open (panel+handle visible). x=drawerWidth: only handle peeks out.
        let base: CGFloat = isOpen ? 0 : drawerWidth
        return max(0, min(drawerWidth, base + dragOffset))
    }

    /// The handle takes the touch from the first point: it lights up at once, the drawer
    /// follows the finger, and a touch that never travels counts as a tap.
    private var handleGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard !kioskManager.showingPINEntry else { return }
                if !isHandlePressed {
                    withAnimation(.easeOut(duration: 0.1)) { isHandlePressed = true }
                }
                dragOffset = value.translation.width
                resetDismissTimer()
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.2)) { isHandlePressed = false }
                guard !kioskManager.showingPINEntry else { return }
                if abs(value.translation.width) < tapSlop {
                    if isOpen { close(animated: true) } else { open() }
                } else {
                    settle(after: value)
                }
            }
    }

    private var panelGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard isOpen, !kioskManager.showingPINEntry else { return }
                dragOffset = value.translation.width
                resetDismissTimer()
            }
            .onEnded { value in
                guard isOpen, !kioskManager.showingPINEntry else { return }
                settle(after: value)
            }
    }

    /// Where a finished drag leaves the drawer: far or fast enough flips it, anything less
    /// springs back to where it started.
    private func settle(after value: DragGesture.Value) {
        let velocity = value.predictedEndTranslation.width - value.translation.width
        let drag = value.translation.width

        if !isOpen {
            if drag < -snapThreshold || velocity < -snapVelocityThreshold {
                open()
            } else {
                withAnimation(snap) { dragOffset = 0 }
            }
        } else {
            if drag > snapThreshold || velocity > snapVelocityThreshold {
                close(animated: true)
            } else {
                withAnimation(snap) { dragOffset = 0 }
                resetDismissTimer()
            }
        }
    }

    private func open() {
        withAnimation(snap) {
            isOpen = true
            dragOffset = 0
        }
        scheduleDismiss()
    }

    private func close(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        if animated {
            withAnimation(snap) {
                isOpen = false
                dragOffset = 0
            }
        } else {
            isOpen = false
            dragOffset = 0
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { close(animated: true) }
        }
    }

    private func resetDismissTimer() {
        guard isOpen else { return }
        scheduleDismiss()
    }

    private func scheduleDelayedClose() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { close(animated: true) }
        }
    }
}

// MARK: - DrawerHandle

private struct DrawerHandle: View {
    let isOpen: Bool
    let isPressed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(isPressed ? 0.3 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(isPressed ? 0.4 : 0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, x: -4, y: 0)

            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPressed ? .primary : .secondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isOpen)
        }
        .environment(\.colorScheme, .dark)
        // Grows under the finger, towards the screen, so the touch is visible past a fingertip.
        .frame(width: isPressed ? 18 : 12, height: isPressed ? 68 : 56)
        // The tab stays slim, but the area that takes the touch is finger-sized.
        .frame(width: 44, height: 96, alignment: .trailing)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(isOpen ? "Close controls" : "Open controls")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - DrawerPanel

private struct DrawerPanel: View {
    var webController: WebViewController
    var onAction: (_ delayedClose: Bool) -> Void

    @EnvironmentObject private var kioskManager: KioskManager
    @EnvironmentObject private var settings: AppSettings

    /// The zoom level, shown beside the panel for a moment after each zoom tap. A zoom step can
    /// be hard to see on a sparse dashboard, and this says it happened.
    @State private var showsZoomLevel = false
    @State private var zoomTaps = 0

    var body: some View {
        VStack(spacing: 0) {
            DrawerButton(symbol: "arrow.clockwise", label: "Refresh", disabled: false, effect: .spin) {
                webController.reload()
                onAction(true)
            }
            divider
            DrawerButton(
                symbol: "house",
                label: "Home",
                disabled: webController.currentURL?.absoluteString == settings.homeURL
            ) {
                webController.goHome(url: settings.homeURL)
                onAction(true)
            }
            divider
            DrawerButton(
                symbol: "plus.magnifyingglass",
                label: "Zoom In",
                disabled: settings.dashboardZoom >= AppSettings.dashboardZoomRange.upperBound
            ) {
                settings.dashboardZoom += AppSettings.dashboardZoomStep
                flashZoomLevel()
                onAction(false)
            }
            divider
            DrawerButton(
                symbol: "minus.magnifyingglass",
                label: "Zoom Out",
                disabled: settings.dashboardZoom <= AppSettings.dashboardZoomRange.lowerBound
            ) {
                settings.dashboardZoom -= AppSettings.dashboardZoomStep
                flashZoomLevel()
                onAction(false)
            }
            divider
            DrawerButton(symbol: "gear", label: "Settings", disabled: false) {
                kioskManager.handleSecretTap()
                onAction(true)
            }
        }
        .frame(width: 72)
        .background(
            UnevenRoundedRectangleCompat(
                topLeadingRadius: 16, bottomLeadingRadius: 16,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                UnevenRoundedRectangleCompat(
                    topLeadingRadius: 16, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 24, x: -4, y: 0)
        )
        .overlay(alignment: .leading) {
            if showsZoomLevel {
                Text("\(settings.dashboardZoom)%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    // Sits to the left of the panel, level with the two zoom buttons.
                    .alignmentGuide(.leading) { $0.width + 12 }
                    .offset(y: 30)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                    .accessibilityHidden(true)
            }
        }
        .task(id: zoomTaps) {
            guard zoomTaps > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showsZoomLevel = false }
        }
    }

    private func flashZoomLevel() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showsZoomLevel = true }
        zoomTaps += 1
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - DrawerButton

private struct DrawerButton: View {
    /// What the symbol does when the button fires, on top of the pressed highlight.
    enum Effect { case bounce, spin }

    let symbol: String
    let label: String
    let disabled: Bool
    var effect: Effect = .bounce
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turns = 0
    @State private var isBounced = false

    var body: some View {
        Button {
            playEffect()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(disabled ? .secondary : .primary)
                .rotationEffect(.degrees(Double(turns) * 360))
                .scaleEffect(isBounced ? 1.3 : 1)
                .frame(width: 72, height: 60)
        }
        .buttonStyle(DrawerButtonStyle())
        .disabled(disabled)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(label)
    }

    private func playEffect() {
        guard !reduceMotion else { return }
        switch effect {
        case .spin:
            withAnimation(.easeInOut(duration: 0.55)) { turns += 1 }
        case .bounce:
            withAnimation(.easeOut(duration: 0.1)) { isBounced = true }
            Task {
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { isBounced = false }
            }
        }
    }
}

/// Lights the button up the moment it is touched and lets go slowly, so even a quick tap shows.
private struct DrawerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0))
                    .padding(5)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: configuration.isPressed ? 0.04 : 0.3), value: configuration.isPressed)
    }
}
