import SwiftUI

struct PINEntryOverlay: View {
    @Environment(KioskManager.self) var kioskManager
    @State private var entered = ""
    @State private var showError = false
    @State private var shakeAmount: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Enter PIN")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                dotRow
                    .offset(x: shakeAmount)

                if showError {
                    Text("Incorrect PIN")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                NumPadView(
                    onDigit: appendDigit,
                    onDelete: deleteDigit,
                    onCancel: { kioskManager.showingPINEntry = false }
                )
            }
            .padding(48)
        }
    }

    // MARK: - Sub-views

    private var dotRow: some View {
        HStack(spacing: 18) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i < entered.count ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 14, height: 14)
            }
        }
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        guard entered.count < 6 else { return }
        entered += digit
        showError = false

        // Auto-validate once we have at least 4 digits and they match the stored PIN length
        // (or immediately if PIN is empty → free access)
        let stored = kioskManager.storedPINLength
        let shouldValidate = entered.count == max(stored, 4)
        if shouldValidate {
            attemptValidation()
        }
    }

    private func deleteDigit() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        showError = false
    }

    private func attemptValidation() {
        if kioskManager.validatePIN(entered) {
            entered = ""
        } else {
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                shakeAmount = 12
            }
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10).delay(0.1)) {
                shakeAmount = 0
            }
            showError = true
            entered = ""
        }
    }
}

// MARK: - Numeric pad

private struct NumPadView: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private let grid = [["1","2","3"], ["4","5","6"], ["7","8","9"], ["cancel","0","del"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(grid, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { key in
                        PadKey(key: key, onDigit: onDigit, onDelete: onDelete, onCancel: onCancel)
                    }
                }
            }
        }
    }
}

private struct PadKey: View {
    let key: String
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button { handleTap() } label: {
            label
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(keyOpacity), in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var label: some View {
        switch key {
        case "del":
            Image(systemName: "delete.left")
                .font(.title3)
                .foregroundStyle(.white)
        case "cancel":
            Text("Cancel")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        default:
            Text(key)
                .font(.title)
                .foregroundStyle(.white)
        }
    }

    private var keyOpacity: Double {
        switch key {
        case "del", "cancel": 0.1
        default: 0.2
        }
    }

    private func handleTap() {
        switch key {
        case "del": onDelete()
        case "cancel": onCancel()
        default: onDigit(key)
        }
    }
}

#Preview {
    PINEntryOverlay()
        .environment(KioskManager())
}
