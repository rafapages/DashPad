// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// OnboardingComponents.swift - the small building blocks of the setup flow's text column:
// headline, eyebrow, fact tiles, option cards, buttons and progress pills.

import SwiftUI

// MARK: - Palette

/// The brand's warm gradient, shared with the marketing site and `AnimatedBlobGradient`.
enum OnboardingPalette {
    static let yellow = Color(hex: "#F6C944")
    static let orange = Color(hex: "#F58A4B")
    static let pink = Color(hex: "#FC4B7F")
    /// Text on the orange button. White on this orange is about 2.5:1, too low to read.
    static let ink = Color(hex: "#1D0A06")
    static let stageBase = Color(hex: "#141516")

    static let gradient = LinearGradient(
        colors: [yellow, orange, pink], startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - Headline

/// A step title whose last words carry the brand gradient: "Wakes when you *walk in.*"
///
/// `Text.foregroundStyle` with a gradient is iOS 17+, so the gradient is drawn as an overlay
/// masked by a second copy of the same text in which only the highlighted words are opaque. Both
/// copies are laid out in the same space, so they wrap identically.
struct OnboardingHeadline: View {
    let plain: String
    let highlight: String
    var size: CGFloat = 40

    var body: some View {
        text(plain: .primary, highlight: .clear)
            .overlay(OnboardingPalette.gradient.mask(text(plain: .clear, highlight: .black)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plain + highlight)
            .accessibilityAddTraits(.isHeader)
    }

    private func text(plain plainColor: Color, highlight highlightColor: Color) -> some View {
        Text("\(Text(plain).foregroundColor(plainColor))\(Text(highlight).foregroundColor(highlightColor))")
            .font(.system(size: size, weight: .heavy))
            .tracking(-size * 0.03)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small uppercase monospaced label that names a step.
struct OnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Facts

/// The gradient dot that marks a claim.
struct BrandDot: View {
    var body: some View {
        Circle()
            .fill(OnboardingPalette.gradient)
            .frame(width: 10, height: 10)
            .background(Circle().fill(OnboardingPalette.pink.opacity(0.12)).padding(-4))
            .accessibilityHidden(true)
    }
}

/// A fact in a tile. Laid out two to a row.
struct FactTile: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A full-width fact with a leading marker: a dot, a step number or an SF Symbol.
struct FactRow: View {
    enum Marker {
        case dot
        case number(Int)
        case symbol(String)
    }

    var marker: Marker = .dot
    var title: String? = nil
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            markerView
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(.body.weight(.semibold))
                }
                Text(text)
                    .font(title == nil ? .callout : .subheadline)
                    .foregroundStyle(title == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case .dot:
            BrandDot()
        case .number(let n):
            Text(String(format: "%02d", n))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(OnboardingPalette.orange)
        case .symbol(let name):
            Image(systemName: name)
                .font(.title3)
                .foregroundStyle(OnboardingPalette.orange)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Choices

/// The orange ring around whichever choice is selected.
struct SelectionRing: ViewModifier {
    let isSelected: Bool
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? OnboardingPalette.orange : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
    }
}

/// A choice with a small picture, a title and a line of description.
struct OptionCard: View {
    let symbol: String
    var symbolTint: Color = OnboardingPalette.orange
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(symbolTint)
                    .frame(width: 76, height: 57)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(SelectionRing(isSelected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A compact choice: a picture with a label underneath. Laid out several to a row.
struct OptionTile<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(SelectionRing(isSelected: isSelected, cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Buttons

/// The footer's buttons: system button styles in a capsule, tinted with the brand orange.
struct OnboardingButton: View {
    let title: String
    var isProminent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isProminent ? OnboardingPalette.ink : Color.primary)
                .frame(maxWidth: .infinity)
        }
        .onboardingButtonStyle(isProminent: isProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(isProminent ? OnboardingPalette.orange : nil)
    }
}

private extension View {
    @ViewBuilder
    func onboardingButtonStyle(isProminent: Bool) -> some View {
        if #available(iOS 26, *) {
            if isProminent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if isProminent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

// MARK: - Progress

struct ProgressPills: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? OnboardingPalette.orange : Color.secondary.opacity(0.4))
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}
