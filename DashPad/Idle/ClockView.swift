// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ClockView.swift - full-screen idle clock. Switches on the clock style; the two classic black faces
// live here, the themed faces in Idle/Clocks/.

import SwiftUI

struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    /// The night screen has a face and theme of its own; the idle screen uses the main ones.
    var isNight = false

    var body: some View {
        let style = isNight ? settings.nightClockStyle : settings.clockStyle
        let appearance = isNight ? settings.nightClockAppearance : settings.clockAppearance

        // Redraw only as often as the face changes: a minute-only face redrawing every second
        // would do 59 invisible redraws a minute for hours on end. `.everyMinute` fires on the
        // minute boundary, so the time is never up to a minute stale.
        if style.updatesEverySecond(with: appearance.options) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                face(style, appearance, at: context.date)
            }
        } else {
            TimelineView(.everyMinute) { context in
                face(style, appearance, at: context.date)
            }
        }
    }

    @ViewBuilder
    private func face(_ style: ClockStyle, _ appearance: ClockAppearance, at date: Date) -> some View {
        if style.isClassic {
            // Drawn at their original size rather than fitted to the design canvas, so they look
            // exactly as they always have, on iPhone too.
            ZStack {
                Color.black.ignoresSafeArea()
                ClassicClockFace(style: style, date: date, hourFormat: appearance.options.hourFormat)
            }
        } else {
            ClockFaceView(style: style, date: date, appearance: appearance, shiftsForBurnIn: true)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Appearance

/// Everything a face reads besides the time and its style.
struct ClockAppearance: Equatable {
    var themes: ClockThemes
    var typeface: ClockTypeface
    var options: ClockOptions
}

extension AppSettings {
    var clockAppearance: ClockAppearance {
        ClockAppearance(themes: clockThemes, typeface: clockTypeface, options: clockOptions)
    }

    /// The idle clock's typeface and options, with the night face drawn in the night theme.
    var nightClockAppearance: ClockAppearance {
        var appearance = clockAppearance
        appearance.themes[nightClockStyle] = nightClockTheme
        return appearance
    }
}

extension ClockStyle {
    /// Faces with something that moves every second: the Numerals seconds hand, and the Sweep
    /// ring, which creeps forward with the seconds.
    func updatesEverySecond(with options: ClockOptions) -> Bool {
        switch self {
        case .numerals: options.showSeconds
        case .sweep: true
        default: false
        }
    }

    /// Faces that write the hour in digits, so 12 or 24-hour time changes what they draw.
    var showsHourDigits: Bool { self != .analog && self != .numerals }
}

// MARK: - Any face, fitted

/// Any clock style drawn into the scaled design canvas: the themed faces on the idle screen,
/// and every face in the Settings preview and style thumbnails.
struct ClockFaceView: View {
    let style: ClockStyle
    let date: Date
    let appearance: ClockAppearance
    /// Idle screen only: nudges the face a few points every 10 minutes against OLED burn-in.
    var shiftsForBurnIn = false

    /// The time thumbnails and previews show when they aren't live: hands spread, all four
    /// digits different.
    static var sampleDate: Date {
        Calendar.current.date(bySettingHour: 10, minute: 9, second: 32, of: Date()) ?? Date()
    }

    var body: some View {
        let theme = appearance.themes[style]
        let typeface = appearance.typeface.resolved(for: style)
        let options = appearance.options
        let label = ClockTime(date, hourFormat: options.hourFormat).accessibilityLabel
        let burnInDate = shiftsForBurnIn ? date : nil

        switch style {
        case .digital, .analog:
            ClockCanvas(accessibilityLabel: label, background: Color.black) { s in
                ClassicClockFace(style: style, date: date, hourFormat: options.hourFormat, scale: s)
                    .designFrame(scale: s)
            }
        case .numerals:
            let c = NumeralsColors.for(theme)
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label, background: c.ground) { s in
                NumeralsClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        case .tiles:
            let c = TilesColors.for(theme)
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label, background: c.bg) { s in
                TilesClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        case .words:
            let c = WordsColors.for(theme)
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label, background: c.bg) { s in
                WordsClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        case .halves:
            let c = HalvesColors.for(theme)
            // Each panel's colour carries on outwards past the canvas.
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label,
                        background: HStack(spacing: 0) { c.a; c.b }) { s in
                HalvesClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        case .sweep:
            let c = SweepColors.for(theme)
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label, background: c.ground) { s in
                SweepClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        case .dots:
            let c = DotsColors.for(theme)
            ClockCanvas(burnInDate: burnInDate, accessibilityLabel: label, background: c.ground) { s in
                DotsClockFace(date: date, colors: c, typeface: typeface, options: options, scale: s)
            }
        }
    }
}

// MARK: - Classic faces

/// Dark Digital and Dark Analog. `scale` is 1 on the idle screen and shrinks them for previews.
private struct ClassicClockFace: View {
    let style: ClockStyle
    let date: Date
    let hourFormat: HourFormat
    var scale: CGFloat = 1

    var body: some View {
        if style == .analog {
            AnalogClockFace(now: date, hourFormat: hourFormat, scale: scale)
        } else {
            DigitalClockFace(now: date, hourFormat: hourFormat, scale: scale)
        }
    }
}

private struct DigitalClockFace: View {
    let now: Date
    let hourFormat: HourFormat
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 12 * scale) {
            Text(hourFormat.timeText(now))
                .font(.system(size: 96 * scale, weight: .thin, design: .default))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(now, format: .dateTime.weekday(.wide).month().day().year())
                .font(scale == 1 ? .title3 : .system(size: 20 * scale))
                .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AnalogClockFace: View {
    let now: Date
    let hourFormat: HourFormat
    let scale: CGFloat

    private var calendar: Calendar { .current }

    private var minutes: Double { Double(calendar.component(.minute, from: now)) }
    private var hours: Double { Double(calendar.component(.hour, from: now)).truncatingRemainder(dividingBy: 12) + minutes / 60 }

    var body: some View {
        let s = scale
        ZStack {
            // Dial
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2 * s)
                .frame(width: 280 * s, height: 280 * s)

            // Hour marks
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2 * s, height: 12 * s)
                    .offset(y: -126 * s)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            ClockHand(angle: .degrees(hours * 30), length: 80 * s, width: 4 * s, color: .white)
            ClockHand(angle: .degrees(minutes * 6), length: 110 * s, width: 3 * s, color: .white)

            Circle().fill(Color.white).frame(width: 10 * s, height: 10 * s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockTime(now, hourFormat: hourFormat).accessibilityLabel)
    }
}

private struct ClockHand: View {
    let angle: Angle
    let length: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(angle)
    }
}

#Preview {
    ClockView()
        .environmentObject(AppSettings())
}
