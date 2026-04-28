import SwiftUI

struct BrowserDrawer: View {
    var webController: WebViewController

    @Environment(KioskManager.self) private var kioskManager
    @Environment(AppSettings.self) private var settings

    @State private var isOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>? = nil

    private let drawerWidth: CGFloat = 72
    private let snapThreshold: CGFloat = 40
    private let snapVelocityThreshold: CGFloat = 300

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
                DrawerHandle(isOpen: isOpen)
                    .gesture(dragGesture)

                DrawerPanel(
                    webController: webController,
                    onAction: { delayedClose in
                        resetDismissTimer()
                        if delayedClose { scheduleDelayedClose() }
                    }
                )
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !kioskManager.showingPINEntry else { return }
                dragOffset = value.translation.width
                resetDismissTimer()
            }
            .onEnded { value in
                guard !kioskManager.showingPINEntry else { return }
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let drag = value.translation.width

                if !isOpen {
                    if drag < -snapThreshold || velocity < -snapVelocityThreshold {
                        open()
                    } else {
                        dragOffset = 0
                    }
                } else {
                    if drag > snapThreshold || velocity > snapVelocityThreshold {
                        close(animated: true)
                    } else {
                        dragOffset = 0
                        resetDismissTimer()
                    }
                }
            }
    }

    private func open() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isOpen = true
            dragOffset = 0
        }
        scheduleDismiss()
    }

    private func close(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
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
            try? await Task.sleep(for: .seconds(4))
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
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            await MainActor.run { close(animated: true) }
        }
    }
}

// MARK: - DrawerHandle

private struct DrawerHandle: View {
    let isOpen: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, x: -4, y: 0)

            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isOpen)
        }
        .frame(width: 12, height: 56)
        // Expand tap area without changing visual size
        .contentShape(Rectangle().inset(by: -12))
    }
}

// MARK: - DrawerPanel

private struct DrawerPanel: View {
    var webController: WebViewController
    var onAction: (_ delayedClose: Bool) -> Void

    @Environment(KioskManager.self) private var kioskManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            DrawerButton(symbol: "arrow.clockwise", label: "Refresh", disabled: false) {
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
            DrawerButton(symbol: "plus.magnifyingglass", label: "Zoom In", disabled: webController.zoomLevel >= 2.0) {
                webController.setZoom(webController.zoomLevel + 0.1)
                onAction(false)
            }
            divider
            DrawerButton(symbol: "minus.magnifyingglass", label: "Zoom Out", disabled: webController.zoomLevel <= 0.5) {
                webController.setZoom(webController.zoomLevel - 0.1)
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
            UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 16,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 24, x: -4, y: 0)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - DrawerButton

private struct DrawerButton: View {
    let symbol: String
    let label: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(disabled ? .secondary : .primary)
                .frame(width: 60, height: 60)
        }
        .disabled(disabled)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(label)
    }
}
