// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

import SwiftUI

// MARK: - Blob definition

private struct Blob {
    var position: UnitPoint  // normalised 0–1 within the view
    var color: Color
    var radius: CGFloat      // as a fraction of view width
}

// MARK: - Three keyframe states parsed from SVG source

// Blur: stdDeviation=90 on 612px canvas → 90/612 = 0.147
// But use ~0.13 to account for the filter overscan region
// making the visible blur appear tighter than the raw value suggests.
private let blurFraction: CGFloat = 0.13

private let keyframes: [[Blob]] = [
    // Frame 1 - yellow centre-left, magenta top-right, magenta bottom-centre
    [
        Blob(position: UnitPoint(x: 0.33, y: 0.41), color: Color(hex: "#F6C944"), radius: 0.60),
        Blob(position: UnitPoint(x: 0.85, y: 0.28), color: Color(hex: "#FC4B7F"), radius: 0.55),
        Blob(position: UnitPoint(x: 0.52, y: 0.78), color: Color(hex: "#FC4B7F"), radius: 0.52),
    ],
    // Frame 2 - yellow bottom-right, magenta top-left, magenta centre-left
    [
        Blob(position: UnitPoint(x: 0.78, y: 0.88), color: Color(hex: "#F6C944"), radius: 0.60),
        Blob(position: UnitPoint(x: 0.28, y: 0.52), color: Color(hex: "#FC4B7F"), radius: 0.55),
        Blob(position: UnitPoint(x: 0.14, y: 0.40), color: Color(hex: "#FC4B7F"), radius: 0.52),
    ],
    // Frame 3 - yellow centre-right, magenta far top-right, magenta bottom-left
    [
        Blob(position: UnitPoint(x: 0.55, y: 0.72), color: Color(hex: "#F6C944"), radius: 0.60),
        Blob(position: UnitPoint(x: 0.95, y: 0.25), color: Color(hex: "#FC4B7F"), radius: 0.55),
        Blob(position: UnitPoint(x: 0.08, y: 0.65), color: Color(hex: "#FC4B7F"), radius: 0.52),
    ],
]

// MARK: - AnimatedBlobGradient

struct AnimatedBlobGradient: View {
    @State private var blobs: [Blob] = keyframes[0]
    @State private var currentFrame = 0

    private let transitionDuration: TimeInterval = 4.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark base - matches SVG background #141516
                Color(hex: "#141516")

                // First pass - normal blend
                blobLayer(blobs: blobs, size: geo.size)

                // Second pass - color-dodge, matching SVG mix-blend-mode
                blobLayer(blobs: blobs, size: geo.size)
                    .blendMode(.colorDodge)
            }
        }
        .onAppear { advance() }
    }

    @ViewBuilder
    private func blobLayer(blobs: [Blob], size: CGSize) -> some View {
        ZStack {
            ForEach(blobs.indices, id: \.self) { i in
                let blob = blobs[i]
                Circle()
                    .fill(blob.color)
                    .frame(
                        width:  blob.radius * size.width,
                        height: blob.radius * size.width
                    )
                    .position(
                        x: blob.position.x * size.width,
                        y: blob.position.y * size.height
                    )
                    .blur(radius: size.width * blurFraction)
            }
        }
    }

    private func advance() {
        let next = (currentFrame + 1) % keyframes.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                blobs = keyframes[next]
            }
            currentFrame = next
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                advance()
            }
        }
    }
}

// MARK: - Hex colour convenience

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    AnimatedBlobGradient()
        .frame(height: 300)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 20
        ))
}
