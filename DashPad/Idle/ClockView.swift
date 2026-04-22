import Combine
import SwiftUI

struct ClockView: View {
    @Environment(AppSettings.self) var settings
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch settings.clockStyle {
            case .digital:
                DigitalClockFace(now: now)
            case .analog:
                AnalogClockFace(now: now)
            }
        }
        .onReceive(ticker) { now = $0 }
    }
}

// MARK: - Digital

private struct DigitalClockFace: View {
    let now: Date

    var body: some View {
        VStack(spacing: 12) {
            Text(now, format: .dateTime.hour().minute().second())
                .font(.system(size: 96, weight: .thin, design: .default))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(now, format: .dateTime.weekday(.wide).month().day().year())
                .font(.title3)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Analog

private struct AnalogClockFace: View {
    let now: Date

    private var calendar: Calendar { .current }

    private var seconds: Double { Double(calendar.component(.second, from: now)) }
    private var minutes: Double { Double(calendar.component(.minute, from: now)) + seconds / 60 }
    private var hours: Double { Double(calendar.component(.hour, from: now)).truncatingRemainder(dividingBy: 12) + minutes / 60 }

    var body: some View {
        ZStack {
            // Dial
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
                .frame(width: 280, height: 280)

            // Hour marks
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2, height: 12)
                    .offset(y: -126)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            ClockHand(angle: .degrees(hours * 30), length: 80, width: 4, color: .white)
            ClockHand(angle: .degrees(minutes * 6), length: 110, width: 3, color: .white)
            ClockHand(angle: .degrees(seconds * 6), length: 120, width: 1.5, color: .red)

            Circle().fill(Color.white).frame(width: 10, height: 10)
        }
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
        .environment(AppSettings())
}
