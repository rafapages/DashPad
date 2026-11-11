// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ClockPickers.swift - the clock style thumbnails and theme swatches, shared by Settings and onboarding.

import SwiftUI

// MARK: - Style

/// A horizontally scrolling row of every clock face, each drawn for real at a fixed time in
/// its own theme, with the current typeface and options.
struct ClockStylePicker: View {
    @Binding var selection: ClockStyle
    let appearance: ClockAppearance
    var thumbnailWidth: CGFloat = 160
    /// Leading and trailing room inside the scroll view, so the first and last thumbnails line
    /// up with the content around the row while the rest can scroll edge to edge.
    var edgeInset: CGFloat = 20
    /// The ring around the chosen face. The setup flow passes its own brand colour.
    var selectionColor: Color = .accentColor

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(ClockStyle.allCases, id: \.self) { style in
                        Button { selection = style } label: { thumbnail(style) }
                            .buttonStyle(.plain)
                            .id(style)
                    }
                }
                .padding(.horizontal, edgeInset)
                .padding(.vertical, 4)
            }
            .onAppear {
                // Start with the chosen face in view, rather than always at Dark Digital.
                if selection != ClockStyle.allCases.first {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    private func thumbnail(_ style: ClockStyle) -> some View {
        let isSelected = style == selection
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return VStack(spacing: 7) {
            ClockFaceView(style: style, date: ClockFaceView.sampleDate, appearance: appearance)
                .frame(width: thumbnailWidth, height: thumbnailWidth / ClockDesign.aspectRatio)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .overlay(alignment: .topLeading) {
                    if style.isClassic { NightFriendlyBadge().padding(6) }
                }
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isSelected ? selectionColor : .clear, lineWidth: 2.5)
                )

            Text(style.displayName)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.isClassic ? "\(style.displayName), night friendly" : style.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Marks the two black faces: mostly black, they give off the least light in a dark room.
struct NightFriendlyBadge: View {
    var body: some View {
        Label("Night friendly", systemImage: "moon.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.indigo)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.indigo.opacity(0.25), in: Capsule())
    }
}

// MARK: - Theme

/// One swatch per theme, drawn from the selected face's own colours so the row changes with
/// the face.
struct ClockThemePicker: View {
    @Binding var selection: ClockTheme
    let style: ClockStyle

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClockTheme.allCases, id: \.self) { theme in
                Button { selection = theme } label: { swatch(theme) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ theme: ClockTheme) -> some View {
        let isSelected = theme == selection
        let colors = theme.swatch(for: style)

        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(colors?.background ?? .black)
                DiagonalHalf().fill(colors?.foreground ?? .white)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .frame(width: 34, height: 34)
            .padding(3)
            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5))

            Text(theme.displayName)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The lower-right half of a square, cut along the diagonal.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
