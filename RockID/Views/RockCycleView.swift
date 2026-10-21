import RockKit
import SwiftUI

/// A simple picture of the rock cycle.
struct RockCycleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Rocks are always changing — just very, very slowly! Over millions of years, any kind of rock can turn into any other kind.")
                    .font(Theme.rounded(21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                CycleDiagram()
                    .frame(height: 560)
                    .card()

                VStack(alignment: .leading, spacing: 14) {
                    step("🌋", "Melting", "Deep underground, rock can melt into magma.")
                    step("🧊", "Cooling", "Magma or lava cools and hardens into igneous rock.")
                    step("🌧️", "Weathering", "Rain, ice, wind, and rivers break rocks into sand, mud, and pebbles.")
                    step("🐚", "Pressing and gluing", "Layers of bits pile up, get squeezed, and are glued into sedimentary rock.")
                    step("🔥", "Heat and squeezing", "Rocks buried deep get heated and squeezed into metamorphic rock, without melting.")
                }
                .card()
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("The Rock Cycle")
    }

    private func step(_ emoji: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(emoji).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rounded(21, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(text).font(Theme.rounded(18, weight: .medium)).foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CycleDiagram: View {
    struct Node {
        let title: String
        let emoji: String
        let color: Color
        let position: CGPoint // unit coordinates
    }

    struct Arrow {
        let from: Int
        let to: Int
        let label: String
    }

    let nodes = [
        Node(title: "Magma", emoji: "🔴", color: Color(hex: 0xD9442B), position: CGPoint(x: 0.5, y: 0.12)),
        Node(title: "Igneous", emoji: "🌋", color: Theme.lava, position: CGPoint(x: 0.85, y: 0.5)),
        Node(title: "Sedimentary", emoji: "🐚", color: Theme.ocean, position: CGPoint(x: 0.5, y: 0.88)),
        Node(title: "Metamorphic", emoji: "🔥", color: Theme.grape, position: CGPoint(x: 0.15, y: 0.5))
    ]

    let arrows = [
        Arrow(from: 0, to: 1, label: "cools"),
        Arrow(from: 1, to: 2, label: "weathers, then\npressed & glued"),
        Arrow(from: 2, to: 3, label: "heat &\nsqueezing"),
        Arrow(from: 3, to: 0, label: "melts"),
        Arrow(from: 1, to: 3, label: "heat & squeezing")
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let point = { (unit: CGPoint) in CGPoint(x: unit.x * size.width, y: unit.y * size.height) }
            ZStack {
                ForEach(arrows.indices, id: \.self) { index in
                    let arrow = arrows[index]
                    let start = point(nodes[arrow.from].position)
                    let end = point(nodes[arrow.to].position)
                    ArrowShape(start: start, end: end, inset: 78)
                        .stroke(Theme.subtleInk, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    Text(arrow.label)
                        .font(Theme.rounded(16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                        .padding(6)
                        .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                        .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                }
                ForEach(nodes.indices, id: \.self) { index in
                    let node = nodes[index]
                    VStack(spacing: 4) {
                        Text(node.emoji).font(.system(size: 40))
                        Text(node.title).font(Theme.rounded(20, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 110)
                    .background(node.color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .position(point(node.position))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rock cycle: magma cools into igneous rock, rocks weather into sediment that becomes sedimentary rock, heat and squeezing make metamorphic rock, and rocks can melt back into magma.")
    }
}

private struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length
        let uy = dy / length
        let from = CGPoint(x: start.x + ux * inset, y: start.y + uy * inset)
        let to = CGPoint(x: end.x - ux * inset, y: end.y - uy * inset)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let head: CGFloat = 16
        let left = CGPoint(x: to.x - ux * head - uy * head * 0.6, y: to.y - uy * head + ux * head * 0.6)
        let right = CGPoint(x: to.x - ux * head + uy * head * 0.6, y: to.y - uy * head - ux * head * 0.6)
        path.move(to: left)
        path.addLine(to: to)
        path.addLine(to: right)
        return path
    }
}
