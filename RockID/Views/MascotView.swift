import SwiftUI

/// "Pebble", the friendly rock detective.
struct MascotView: View {
    var size: CGFloat = 140
    var isSearching = false

    @State private var bounce = false
    @State private var glassAngle: Double = -20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Body
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xC9C2B6), Color(hex: 0x948B7E)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size * 0.82)
                .overlay(
                    Ellipse()
                        .stroke(Color(hex: 0x6E665B), lineWidth: size * 0.03)
                )
                // Little speckles so Pebble looks like granite.
                .overlay(speckles)

            // Eyes
            HStack(spacing: size * 0.18) {
                eye
                eye
            }
            .offset(y: -size * 0.08)

            // Cheeks
            HStack(spacing: size * 0.42) {
                Circle().fill(Color(hex: 0xF4A0A0).opacity(0.7)).frame(width: size * 0.12)
                Circle().fill(Color(hex: 0xF4A0A0).opacity(0.7)).frame(width: size * 0.12)
            }
            .offset(y: size * 0.08)

            // Smile
            SmileShape()
                .stroke(Color(hex: 0x3A2E25), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.28, height: size * 0.1)
                .offset(y: size * 0.12)

            if isSearching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(Theme.lava)
                    .rotationEffect(.degrees(glassAngle))
                    .offset(x: size * 0.48, y: size * 0.22)
            }
        }
        .frame(width: size * 1.3, height: size)
        .offset(y: bounce ? -size * 0.05 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                bounce = true
                glassAngle = 20
            }
        }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.2)
            Circle().fill(Color(hex: 0x2B211A)).frame(width: size * 0.1).offset(x: size * 0.02, y: size * 0.01)
            Circle().fill(.white).frame(width: size * 0.035).offset(x: size * 0.045, y: -size * 0.02)
        }
    }

    private var speckles: some View {
        Canvas { context, canvasSize in
            let points: [(CGFloat, CGFloat, Bool)] = [
                (0.18, 0.3, true), (0.25, 0.7, false), (0.4, 0.82, true), (0.62, 0.86, false),
                (0.8, 0.62, true), (0.84, 0.32, false), (0.7, 0.16, true), (0.3, 0.14, false),
                (0.12, 0.52, false), (0.9, 0.48, true), (0.55, 0.92, true)
            ]
            for (x, y, dark) in points {
                let dot = CGRect(x: x * canvasSize.width, y: y * canvasSize.height, width: size * 0.035, height: size * 0.035)
                context.fill(Path(ellipseIn: dot), with: .color(dark ? Color(hex: 0x4A433B) : .white.opacity(0.8)))
            }
        }
        .frame(width: size, height: size * 0.82)
        .clipShape(Ellipse())
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}
