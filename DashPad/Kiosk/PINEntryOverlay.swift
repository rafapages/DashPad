import SwiftUI

struct PINEntryOverlay: View {
    @Environment(KioskManager.self) var kioskManager
    @State private var entered = ""
    @State private var showError = false
    @State private var shakeAmount: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 48) {
                VStack(spacing: 16) {
                    Text("Enter PIN")
                        .font(.title2.weight(.semibold))

                    dotRow
                        .offset(x: shakeAmount)

                    // Fixed-height slot keeps layout stable whether error shows or not
                    Text(showError ? "Incorrect PIN" : " ")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .animation(.default, value: showError)
                }

                NumPadView(
                    onDigit: appendDigit,
                    onDelete: deleteDigit,
                    onCancel: { kioskManager.showingPINEntry = false }
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Dot row

    private var dotRow: some View {
        HStack(spacing: 18) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i < entered.count ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 14, height: 14)
                    .animation(.spring(duration: 0.2), value: entered.count)
            }
        }
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        guard entered.count < 6 else { return }
        entered += digit
        showError = false

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

    private let rows = [["1","2","3"], ["4","5","6"], ["7","8","9"], ["cancel","0","del"]]

    var body: some View {
        // Grid ensures every column is the same width regardless of button style
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        PadKey(key: key, onDigit: onDigit, onDelete: onDelete, onCancel: onCancel)
                    }
                }
            }
        }
    }
}

// MARK: - Individual key

private struct PadKey: View {
    let key: String
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if key == "cancel" {
            Button("Cancel") { onCancel() }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        } else {
            Button(action: handleTap) {
                keyLabel
                    .frame(width: 80, height: 80)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    @ViewBuilder
    private var keyLabel: some View {
        if key == "del" {
            Image(systemName: "delete.left")
                .font(.title3)
        } else {
            Text(key)
                .font(.title)
        }
    }

    private func handleTap() {
        switch key {
        case "del": onDelete()
        default:    onDigit(key)
        }
    }
}

#Preview {
    PINEntryOverlay()
        .environment(KioskManager())
}
