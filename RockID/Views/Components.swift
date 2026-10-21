import RockKit
import SwiftUI

/// Igneous / Sedimentary / Metamorphic capsule.
struct FamilyBadge: View {
    let family: RockFamily
    var large = false

    var body: some View {
        Text("\(family.emoji) \(family.displayName)")
            .font(Theme.rounded(large ? 20 : 15, weight: .heavy))
            .padding(.horizontal, large ? 16 : 12)
            .padding(.vertical, large ? 8 : 5)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .background(Theme.color(for: family), in: Capsule())
            .accessibilityLabel("\(family.displayName) rock")
    }
}

struct StarsView: View {
    let count: Int
    var total = 3
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(index < count ? Theme.sunshine : Theme.subtleInk.opacity(0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) out of \(total) stars")
    }
}

/// Small rounded label with an emoji.
struct Chip: View {
    let emoji: String
    let text: String
    var color: Color = Theme.softCard

    var body: some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(text)
                .font(Theme.rounded(17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color, in: Capsule())
    }
}

/// Section heading used on cards.
struct CardTitle: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 28))
            Text(text)
                .font(Theme.rounded(24, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Bursts of emoji when a rock is identified.
struct CelebrationView: View {
    let trigger: Int
    @State private var particles: [Particle] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Particle: Identifiable {
        let id = UUID()
        let emoji: String
        let angle: Double
        let distance: CGFloat
        var launched = false
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Text(particle.emoji)
                    .font(.system(size: 34))
                    .offset(
                        x: particle.launched ? cos(particle.angle) * particle.distance : 0,
                        y: particle.launched ? sin(particle.angle) * particle.distance : 0
                    )
                    .opacity(particle.launched ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        guard !reduceMotion else { return }
        let emojis = ["✨", "⭐️", "🪨", "💎", "🎉"]
        particles = (0..<18).map { index in
            Particle(
                emoji: emojis[index % emojis.count],
                angle: Double(index) / 18 * 2 * .pi,
                distance: CGFloat.random(in: 140...260)
            )
        }
        withAnimation(.easeOut(duration: 1.2)) {
            for index in particles.indices { particles[index].launched = true }
        }
    }
}
