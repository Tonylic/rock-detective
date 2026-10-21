import CoreGraphics
import Foundation

/// Draws friendly, deterministic illustrations of each rock that show its real
/// diagnostic texture (speckles, layers, bubble holes, bands, pebbles …).
/// Pure Core Graphics, so it works in the app, in tests, and on any thread.
public enum RockArtRenderer {
    /// Rock-shaped illustration with shading, on a transparent background.
    public static func render(_ style: RockArtStyle, size: Int) -> CGImage? {
        guard size > 0, let context = makeContext(width: size, height: size) else { return nil }
        let full = CGRect(x: 0, y: 0, width: size, height: size)
        var rng = SeededGenerator(seed: style.seed &* 7919 &+ 17)
        let outline = rockPath(in: full.insetBy(dx: CGFloat(size) * 0.04, dy: CGFloat(size) * 0.1), rng: &rng)

        // Soft shadow under the rock.
        context.saveGState()
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.16))
        context.fillEllipse(in: CGRect(
            x: CGFloat(size) * 0.14, y: CGFloat(size) * 0.05,
            width: CGFloat(size) * 0.72, height: CGFloat(size) * 0.12
        ))
        context.restoreGState()

        context.saveGState()
        context.addPath(outline)
        context.clip()
        var painter = Painter(context: context, rect: full, style: style)
        painter.paint()
        shade(context: context, rect: full)
        context.restoreGState()

        context.addPath(outline)
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        context.setLineWidth(max(1, CGFloat(size) / 170))
        context.strokePath()
        return context.makeImage()
    }

    /// The texture alone, filling the whole square.
    public static func renderTexture(_ style: RockArtStyle, size: Int) -> CGImage? {
        guard size > 0, let context = makeContext(width: size, height: size) else { return nil }
        var painter = Painter(context: context, rect: CGRect(x: 0, y: 0, width: size, height: size), style: style)
        painter.paint()
        return context.makeImage()
    }

    /// The illustration lying on a table, as a pretend photo for practice and UI tests.
    public static func renderPracticePhoto(_ style: RockArtStyle, size: Int) -> CGImage? {
        guard size > 0, let context = makeContext(width: size, height: size),
              let rock = render(style, size: Int(Double(size) * 0.92)) else { return nil }
        let full = CGRect(x: 0, y: 0, width: size, height: size)
        let colors = [color("#CDB38D"), color("#B8976B")] as CFArray
        if let gradient = CGGradient(colorsSpace: ImageLoader.sRGB, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
        }
        let inset = CGFloat(size) * 0.04
        context.draw(rock, in: full.insetBy(dx: inset, dy: inset))
        return context.makeImage()
    }

    // MARK: - Helpers

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: ImageLoader.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Parses "#RRGGBB" into an sRGB color.
    public static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let components = rgb(hex)
        return CGColor(srgbRed: components.r, green: components.g, blue: components.b, alpha: alpha)
    }

    public static func rgb(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return (0.5, 0.5, 0.5) }
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }

    /// A smooth, lumpy, pebble-like outline.
    static func rockPath(in rect: CGRect, rng: inout SeededGenerator) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pointCount = 11
        var points: [CGPoint] = []
        for i in 0..<pointCount {
            let angle = Double(i) / Double(pointCount) * 2 * .pi + rng.range(-0.15...0.15)
            let radius = rng.range(0.8...1.0)
            points.append(CGPoint(
                x: center.x + CGFloat(cos(angle) * radius) * rect.width / 2,
                y: center.y + CGFloat(sin(angle) * radius) * rect.height / 2
            ))
        }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let path = CGMutablePath()
        path.move(to: midpoint(points[pointCount - 1], points[0]))
        for i in 0..<pointCount {
            path.addQuadCurve(to: midpoint(points[i], points[(i + 1) % pointCount]), control: points[i])
        }
        path.closeSubpath()
        return path
    }

    /// Light from the top-left, shadow at the bottom-right, for a 3-D look.
    static func shade(context: CGContext, rect: CGRect) {
        let colors = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.32)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: ImageLoader.sRGB, colors: colors, locations: [0, 0.45, 1]) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
}

/// Paints one rock texture into a context.
private struct Painter {
    let context: CGContext
    let rect: CGRect
    let style: RockArtStyle
    var rng: SeededGenerator
    /// Scale relative to a 512-pixel canvas.
    let s: Double

    init(context: CGContext, rect: CGRect, style: RockArtStyle) {
        self.context = context
        self.rect = rect
        self.style = style
        self.rng = SeededGenerator(seed: style.seed)
        self.s = Double(rect.width) / 512
    }

    var base: CGColor { RockArtRenderer.color(style.base) }

    func accent(_ index: Int, alpha: CGFloat = 1) -> CGColor {
        guard !style.accents.isEmpty else { return RockArtRenderer.color(style.base, alpha: alpha) }
        return RockArtRenderer.color(style.accents[index % style.accents.count], alpha: alpha)
    }

    var accentCount: Int { max(1, style.accents.count) }

    mutating func paint() {
        context.setFillColor(base)
        context.fill(rect)
        switch style.pattern {
        case .speckled:
            crystals(count: 1100, size: 5...15, colors: Array(0..<accentCount))
        case .fine:
            dots(count: 4200, radius: 0.6...1.6, colors: Array(0..<accentCount), alpha: 0.6)
        case .porphyritic:
            dots(count: 3600, radius: 0.6...1.6, colors: [2], alpha: 0.6)
            crystals(count: 70, size: 4...11, colors: [0], elongation: 2.2)
            crystals(count: 28, size: 3...8, colors: [1], elongation: 1.8)
        case .flowBanded:
            bands(thickness: 6...22, amplitude: 14, wavelength: 260, angle: -0.15, colors: Array(0..<accentCount), alpha: 0.55)
            dots(count: 2500, radius: 0.6...1.4, colors: [0, 2], alpha: 0.4)
        case .glassy:
            conchoidalArcs(count: 6, color: accent(1, alpha: 0.55))
            glassHighlights(count: 5)
        case .vesicular:
            dots(count: 1500, radius: 0.6...1.4, colors: [1], alpha: 0.5)
            holes(count: 260, radius: 3...15, hole: accent(0), rim: accent(2, alpha: 0.9))
        case .ash:
            dots(count: 3200, radius: 0.6...1.5, colors: Array(0..<accentCount), alpha: 0.5)
            crystals(count: 60, size: 3...9, colors: [1, 0])
            holes(count: 25, radius: 2...5, hole: accent(0, alpha: 0.7), rim: accent(2, alpha: 0.7))
        case .crossBedded:
            crossBeds()
            dots(count: 3600, radius: 0.7...1.8, colors: Array(0..<accentCount), alpha: 0.55)
        case .fissile:
            bands(thickness: 3...9, amplitude: 2, wavelength: 400, angle: 0.05, colors: Array(0..<accentCount), alpha: 0.75)
            partings(count: 22, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35), width: 1.2, angle: 0.05)
        case .roundClasts:
            dots(count: 2600, radius: 0.7...1.8, colors: [1, 3], alpha: 0.55)
            clasts(count: 55, size: 34...84, rounded: true)
        case .angularClasts:
            dots(count: 2200, radius: 0.7...1.6, colors: [1], alpha: 0.4)
            clasts(count: 50, size: 34...84, rounded: false)
        case .fossiliferous:
            bands(thickness: 40...90, amplitude: 4, wavelength: 500, angle: 0.03, colors: [0, 1], alpha: 0.22)
            dots(count: 2200, radius: 0.6...1.5, colors: [0, 2], alpha: 0.45)
            fossils(count: 12)
        case .chalky:
            dots(count: 2600, radius: 0.6...1.6, colors: [0], alpha: 0.5)
            flintNodules(count: 2)
        case .coal:
            bands(thickness: 8...26, amplitude: 1.5, wavelength: 500, angle: 0.02, colors: [0, 1], alpha: 0.55)
            partings(count: 14, color: accent(2, alpha: 0.55), width: 1.4, angle: 0.02)
            cleats(count: 9)
        case .waxy:
            mottles(count: 30)
            conchoidalArcs(count: 4, color: accent(0, alpha: 0.4))
            softHighlight()
        case .slaty:
            bands(thickness: 2...6, amplitude: 0.5, wavelength: 600, angle: 0.12, colors: Array(0..<accentCount), alpha: 0.5)
            partings(count: 5, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45), width: 2, angle: 0.12)
        case .sheen:
            bands(thickness: 4...12, amplitude: 9, wavelength: 90, angle: 0.08, colors: [0, 2, 3], alpha: 0.5)
            bands(thickness: 10...26, amplitude: 9, wavelength: 90, angle: 0.08, colors: [1], alpha: 0.18, gap: 30...70)
        case .schistose:
            bands(thickness: 6...14, amplitude: 10, wavelength: 140, angle: 0.05, colors: [0, 1], alpha: 0.35)
            micaFlakes(rows: 26)
            sparkles(count: 140)
            garnets(count: 10)
        case .banded:
            bands(thickness: 14...46, amplitude: 22, wavelength: 300, angle: 0.18, colors: [0, 1, 2, 1], alpha: 0.92)
            crystals(count: 650, size: 3...8, colors: Array(0..<accentCount), alpha: 0.55)
        case .veined:
            // Unpolished marble: interlocking, sugary calcite crystals with veins.
            crystals(count: 2200, size: 4...10, colors: [0, 1, 2], alpha: 0.6)
            veins(count: 7)
            sparkles(count: 90)
        case .sugary:
            crystals(count: 1600, size: 3...8, colors: Array(0..<accentCount), alpha: 0.7)
            sparkles(count: 120)
        }
    }

    // MARK: - Primitives

    mutating func point() -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(rng.unit()) * rect.width, y: rect.minY + CGFloat(rng.unit()) * rect.height)
    }

    mutating func pick(_ colors: [Int]) -> Int {
        colors[Int(rng.unit() * Double(colors.count)) % colors.count]
    }

    mutating func dots(count: Int, radius: ClosedRange<Double>, colors: [Int], alpha: CGFloat) {
        for _ in 0..<count {
            let center = point()
            let r = CGFloat(rng.range(radius) * s)
            context.setFillColor(accent(pick(colors), alpha: alpha))
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// Small polygons: mineral crystals or sand grains.
    mutating func crystals(count: Int, size: ClosedRange<Double>, colors: [Int], alpha: CGFloat = 1, elongation: Double = 1) {
        for _ in 0..<count {
            let center = point()
            let radius = rng.range(size) * s / 2
            let sides = 4 + Int(rng.unit() * 3)
            let rotation = rng.range(0...(2 * .pi))
            let path = CGMutablePath()
            for i in 0..<sides {
                let angle = Double(i) / Double(sides) * 2 * .pi + rng.range(-0.3...0.3)
                let r = radius * rng.range(0.7...1.0)
                let x = cos(angle) * r * elongation
                let y = sin(angle) * r
                let rotated = CGPoint(
                    x: center.x + CGFloat(x * cos(rotation) - y * sin(rotation)),
                    y: center.y + CGFloat(x * sin(rotation) + y * cos(rotation))
                )
                if i == 0 { path.move(to: rotated) } else { path.addLine(to: rotated) }
            }
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(accent(pick(colors), alpha: alpha))
            context.fillPath()
        }
    }

    /// Wavy layers stacked across (and beyond) the canvas, then rotated.
    mutating func bands(
        thickness: ClosedRange<Double>,
        amplitude: Double,
        wavelength: Double,
        angle: Double,
        colors: [Int],
        alpha: CGFloat,
        gap: ClosedRange<Double> = 0...0
    ) {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(angle))
        let extent = Double(rect.width)
        var y = -extent
        var index = 0
        let phase = rng.range(0...(2 * .pi))
        while y < extent {
            let t = rng.range(thickness) * s
            let path = CGMutablePath()
            let step = 6.0 * s
            var x = -extent
            let scale = s
            let wave = { (x: Double, offset: Double) -> Double in
                offset + amplitude * scale * sin(2 * .pi * x / (wavelength * scale) + phase)
            }
            path.move(to: CGPoint(x: x, y: wave(x, y)))
            while x <= extent {
                x += step
                path.addLine(to: CGPoint(x: x, y: wave(x, y)))
            }
            while x >= -extent {
                path.addLine(to: CGPoint(x: x, y: wave(x, y + t)))
                x -= step
            }
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(accent(colors[index % colors.count], alpha: alpha))
            context.fillPath()
            y += t + rng.range(gap) * s
            index += 1
        }
        context.restoreGState()
    }

    /// Thin straight lines across the canvas (partings, shiny coal layers).
    mutating func partings(count: Int, color: CGColor, width: Double, angle: Double) {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(angle))
        context.setStrokeColor(color)
        context.setLineWidth(CGFloat(width * s))
        let extent = Double(rect.width)
        for _ in 0..<count {
            let y = rng.range(-extent / 2...extent / 2)
            context.move(to: CGPoint(x: -extent, y: y))
            context.addLine(to: CGPoint(x: extent, y: y + rng.range(-3...3) * s))
        }
        context.strokePath()
        context.restoreGState()
    }

    /// Sets of slanted laminae between flat bedding planes.
    mutating func crossBeds() {
        let bedCount = 4
        let bedHeight = Double(rect.height) / Double(bedCount)
        for bed in 0..<bedCount {
            let bottom = Double(rect.minY) + Double(bed) * bedHeight
            context.saveGState()
            context.clip(to: CGRect(x: Double(rect.minX), y: bottom, width: Double(rect.width), height: bedHeight))
            context.setLineWidth(CGFloat(2.5 * s))
            let spacing = 8 * s
            var x = Double(rect.minX) - bedHeight
            var index = 0
            while x < Double(rect.maxX) + bedHeight {
                context.setStrokeColor(accent(index % accentCount, alpha: 0.45))
                context.move(to: CGPoint(x: x, y: bottom))
                context.addLine(to: CGPoint(x: x + bedHeight * 0.45, y: bottom + bedHeight))
                context.strokePath()
                x += spacing
                index += 1
            }
            context.restoreGState()
            context.setStrokeColor(accent(2, alpha: 0.7))
            context.setLineWidth(CGFloat(3 * s))
            context.move(to: CGPoint(x: Double(rect.minX), y: bottom))
            context.addLine(to: CGPoint(x: Double(rect.maxX), y: bottom))
            context.strokePath()
        }
    }

    mutating func holes(count: Int, radius: ClosedRange<Double>, hole: CGColor, rim: CGColor) {
        for _ in 0..<count {
            let center = point()
            let r = rng.range(radius) * s
            let squash = rng.range(0.7...1.0)
            let rimRect = CGRect(x: center.x - CGFloat(r * 1.15), y: center.y - CGFloat(r * squash * 1.15),
                                 width: CGFloat(2.3 * r), height: CGFloat(2.3 * r * squash))
            context.setFillColor(rim)
            context.fillEllipse(in: rimRect.offsetBy(dx: CGFloat(-r * 0.15), dy: CGFloat(r * 0.15)))
            context.setFillColor(hole)
            context.fillEllipse(in: CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r * squash),
                                           width: CGFloat(2 * r), height: CGFloat(2 * r * squash)))
        }
    }

    /// Pebbles (rounded) or broken fragments (angular).
    mutating func clasts(count: Int, size: ClosedRange<Double>, rounded: Bool) {
        for i in 0..<count {
            let center = point()
            let radius = rng.range(size) * s / 2
            let path = CGMutablePath()
            if rounded {
                let squash = rng.range(0.6...0.95)
                let rotation = rng.range(0...(.pi))
                let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(rotation))
                path.addEllipse(in: CGRect(x: -radius, y: -radius * squash, width: 2 * radius, height: 2 * radius * squash),
                                transform: transform)
            } else {
                let sides = 3 + Int(rng.unit() * 3)
                for j in 0..<sides {
                    let angle = Double(j) / Double(sides) * 2 * .pi + rng.range(-0.4...0.4)
                    let r = radius * rng.range(0.6...1.1)
                    let p = CGPoint(x: center.x + CGFloat(cos(angle) * r), y: center.y + CGFloat(sin(angle) * r))
                    if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
            }
            context.addPath(path)
            context.setFillColor(accent(i % accentCount))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
            context.setLineWidth(CGFloat(1.5 * s))
            context.strokePath()
            if rounded {
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25))
                let r = radius * 0.3
                context.fillEllipse(in: CGRect(x: center.x - CGFloat(radius * 0.45), y: center.y + CGFloat(radius * 0.15),
                                               width: CGFloat(r), height: CGFloat(r * 0.7)))
            }
        }
    }

    /// Fan-shaped shells and round crinoid discs.
    mutating func fossils(count: Int) {
        for i in 0..<count {
            let center = point()
            let radius = rng.range(22...40) * s
            let rotation = rng.range(0...(2 * .pi))
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(rotation))
            if i % 3 == 2 {
                context.setFillColor(accent(1))
                context.fillEllipse(in: CGRect(x: -radius / 2, y: -radius / 2, width: radius, height: radius))
                context.setStrokeColor(accent(2))
                context.setLineWidth(CGFloat(2 * s))
                context.strokeEllipse(in: CGRect(x: -radius / 2, y: -radius / 2, width: radius, height: radius))
                context.setFillColor(accent(2))
                context.fillEllipse(in: CGRect(x: -radius / 8, y: -radius / 8, width: radius / 4, height: radius / 4))
            } else {
                let shell = CGMutablePath()
                shell.move(to: .zero)
                shell.addArc(center: .zero, radius: CGFloat(radius), startAngle: 0.35, endAngle: .pi - 0.35, clockwise: false)
                shell.closeSubpath()
                context.addPath(shell)
                context.setFillColor(accent(1))
                context.fillPath()
                context.addPath(shell)
                context.setStrokeColor(accent(2))
                context.setLineWidth(CGFloat(2 * s))
                context.strokePath()
                context.setStrokeColor(accent(2))
                context.setLineWidth(CGFloat(1.4 * s))
                for rib in 0..<7 {
                    let angle = 0.45 + Double(rib) / 6 * (.pi - 0.9)
                    context.move(to: .zero)
                    context.addLine(to: CGPoint(x: cos(angle) * radius * 0.95, y: sin(angle) * radius * 0.95))
                }
                context.strokePath()
            }
            context.restoreGState()
        }
    }

    mutating func flintNodules(count: Int) {
        for _ in 0..<count {
            let center = point()
            let radius = rng.range(30...50) * s
            let path = CGMutablePath()
            let sides = 9
            for j in 0..<sides {
                let angle = Double(j) / Double(sides) * 2 * .pi
                let r = radius * rng.range(0.65...1.0)
                let p = CGPoint(x: center.x + CGFloat(cos(angle) * r * 1.3), y: center.y + CGFloat(sin(angle) * r * 0.8))
                if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            context.addPath(path)
            context.setStrokeColor(accent(2))
            context.setLineWidth(CGFloat(6 * s))
            context.strokePath()
            context.addPath(path)
            context.setFillColor(accent(1))
            context.fillPath()
        }
    }

    /// Vertical cracks typical of coal (cleats).
    mutating func cleats(count: Int) {
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.75))
        context.setLineWidth(CGFloat(1.5 * s))
        for _ in 0..<count {
            let start = point()
            context.move(to: start)
            context.addLine(to: CGPoint(x: start.x + CGFloat(rng.range(-6...6) * s), y: start.y + CGFloat(rng.range(40...120) * s)))
        }
        context.strokePath()
    }

    /// Curved ripple marks of a shell-like (conchoidal) fracture.
    mutating func conchoidalArcs(count: Int, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(CGFloat(2 * s))
        for _ in 0..<count {
            let center = point()
            let start = rng.range(0...(2 * .pi))
            for ring in 1...4 {
                let radius = CGFloat(Double(ring) * rng.range(14...22) * s)
                context.addArc(center: center, radius: radius, startAngle: CGFloat(start), endAngle: CGFloat(start + 1.6), clockwise: false)
                context.strokePath()
            }
        }
    }

    /// Bright, colourless reflections of glass, mostly near the middle.
    mutating func glassHighlights(count: Int) {
        for _ in 0..<count {
            let center = CGPoint(
                x: rect.midX + CGFloat(rng.range(-0.25...0.25)) * rect.width,
                y: rect.midY + CGFloat(rng.range(-0.25...0.25)) * rect.height
            )
            let length = rng.range(50...90) * s
            let width = rng.range(7...13) * s
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(rng.range(0.4...0.9)))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2))
            context.fillEllipse(in: CGRect(x: -length * 0.65, y: -width * 1.4, width: length * 1.3, height: width * 2.8))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: -length / 2, y: -width / 2, width: length, height: width))
            context.restoreGState()
        }
    }

    mutating func mottles(count: Int) {
        for i in 0..<count {
            let center = point()
            let radius = rng.range(20...60) * s
            context.setFillColor(accent(i % 2, alpha: 0.3))
            context.fillEllipse(in: CGRect(x: center.x - CGFloat(radius), y: center.y - CGFloat(radius * 0.7),
                                           width: CGFloat(2 * radius), height: CGFloat(1.4 * radius)))
        }
    }

    mutating func softHighlight() {
        let center = CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.62)
        for step in 0..<6 {
            let radius = CGFloat((90 - Double(step) * 13) * s)
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.6, width: 2 * radius, height: 1.2 * radius))
        }
    }

    /// Aligned shiny mica flakes along wavy foliation.
    mutating func micaFlakes(rows: Int) {
        let rowSpacing = Double(rect.height) / Double(rows)
        for row in 0..<rows {
            let baseY = Double(rect.minY) + (Double(row) + 0.5) * rowSpacing
            let phase = rng.range(0...(2 * .pi))
            var x = Double(rect.minX)
            while x < Double(rect.maxX) {
                let y = baseY + 10 * s * sin(2 * .pi * x / (140 * s) + phase)
                let slope = atan(10 * s * 2 * .pi / (140 * s) * cos(2 * .pi * x / (140 * s) + phase))
                let length = rng.range(8...16) * s
                context.saveGState()
                context.translateBy(x: CGFloat(x), y: CGFloat(y + rng.range(-4...4) * s))
                context.rotate(by: CGFloat(slope))
                context.setFillColor(accent(Int(rng.unit() * 2), alpha: 0.85))
                context.fillEllipse(in: CGRect(x: -length / 2, y: -1.6 * s, width: length, height: 3.2 * s))
                context.restoreGState()
                x += rng.range(6...12) * s
            }
        }
    }

    mutating func sparkles(count: Int) {
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        for _ in 0..<count {
            let center = point()
            let size = rng.range(3...7) * s
            context.fill(CGRect(x: center.x - CGFloat(size / 2), y: center.y - CGFloat(s / 2), width: CGFloat(size), height: CGFloat(s)))
            context.fill(CGRect(x: center.x - CGFloat(s / 2), y: center.y - CGFloat(size / 2), width: CGFloat(s), height: CGFloat(size)))
        }
    }

    mutating func garnets(count: Int) {
        for _ in 0..<count {
            let center = point()
            let radius = rng.range(5...9) * s
            let rect = CGRect(x: center.x - CGFloat(radius), y: center.y - CGFloat(radius), width: CGFloat(2 * radius), height: CGFloat(2 * radius))
            context.setFillColor(accent(3))
            context.fillEllipse(in: rect)
            context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4))
            context.setLineWidth(CGFloat(1.2 * s))
            context.strokeEllipse(in: rect)
        }
    }

    mutating func veins(count: Int) {
        context.setLineCap(.round)
        for i in 0..<count {
            let start = CGPoint(x: rect.minX - 10, y: rect.minY + CGFloat(rng.unit()) * rect.height)
            let end = CGPoint(x: rect.maxX + 10, y: rect.minY + CGFloat(rng.unit()) * rect.height)
            let control1 = point()
            let control2 = point()
            context.move(to: start)
            context.addCurve(to: end, control1: control1, control2: control2)
            context.setStrokeColor(accent(i % 2, alpha: 0.6))
            context.setLineWidth(CGFloat(rng.range(1.5...5) * s))
            context.strokePath()
        }
    }
}
