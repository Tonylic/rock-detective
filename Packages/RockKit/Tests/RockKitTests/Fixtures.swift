import CoreGraphics
import Foundation
import ImageIO
import Vision
@testable import RockKit

enum Fixtures {
    // The bundled catalog is validated by KB-01; a failure here means that test fails too.
    static let catalog: RockCatalog = {
        do {
            return try RockCatalog.bundled()
        } catch {
            fatalError("Bundled catalog failed to load: \(error)")
        }
    }()

    static let matcher = RockMatcher(catalog: catalog)
    static let planner = QuestionPlanner(matcher: matcher)
    static let identifier = RockIdentifier(catalog: catalog)

    static func rock(_ id: String) -> Rock {
        guard let rock = catalog.rock(id: id) else { fatalError("Unknown rock \(id)") }
        return rock
    }

    static func question(_ id: ClueID) -> ClueQuestion {
        guard let question = catalog.question(id) else { fatalError("Unknown question \(id)") }
        return question
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RockKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    static let subjectFinderAvailable: Bool = {
        guard let image = TestImages.speckles(size: 64, seed: 2) else { return false }
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        return (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil
    }()

    static let visionAvailable: Bool = {
        guard let image = TestImages.speckles(size: 64, seed: 1) else { return false }
        return (try? FeaturePrinter.vector(for: image)) != nil
    }()
}

/// A pretend kid who answers questions about a known rock, following that
/// rock's clue probabilities, with an optional rate of random answers.
struct SimulatedKid {
    let rock: Rock
    var rng: SeededGenerator
    var mistakeRate: Double

    init(rock: Rock, seed: UInt64, mistakeRate: Double = 0) {
        self.rock = rock
        self.rng = SeededGenerator(seed: seed)
        self.mistakeRate = mistakeRate
    }

    mutating func answer(_ question: ClueQuestion) -> Answer {
        let outcomes = question.outcomes
        if rng.unit() < mistakeRate {
            return outcomes[Int(rng.unit() * Double(outcomes.count)) % outcomes.count]
        }
        var u = rng.unit()
        for outcome in outcomes {
            let p = rock.clues.probability(of: outcome, for: question.id) ?? 0
            if u < p { return outcome }
            u -= p
        }
        return outcomes[outcomes.count - 1]
    }

    /// Answers every question that applies, in catalog order.
    mutating func answerEverything(catalog: RockCatalog) -> Evidence {
        var evidence = Evidence()
        for question in catalog.questions {
            if let requirement = question.requires, evidence.answers[requirement.clue] != requirement.answer {
                continue
            }
            evidence.answers[question.id] = answer(question)
        }
        return evidence
    }
}

/// Synthetic images drawn with Core Graphics.
enum TestImages {
    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func uniform(red: CGFloat, green: CGFloat, blue: CGFloat, width: Int = 400, height: Int = 400) -> CGImage? {
        guard let ctx = context(width: width, height: height) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func gray(_ value: CGFloat, size: Int = 400) -> CGImage? {
        uniform(red: value, green: value, blue: value, width: size, height: size)
    }

    /// Alternating light and dark stripes, rotated by `angle` radians.
    static func stripes(size: Int = 400, period: CGFloat = 24, angle: CGFloat = 0) -> CGImage? {
        guard let ctx = context(width: size, height: size) else { return nil }
        let extent = CGFloat(size)
        ctx.setFillColor(CGColor(srgbRed: 0.75, green: 0.72, blue: 0.68, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: extent, height: extent))
        ctx.translateBy(x: extent / 2, y: extent / 2)
        ctx.rotate(by: angle)
        ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.28, blue: 0.27, alpha: 1))
        var y = -extent
        while y < extent {
            ctx.fill(CGRect(x: -extent, y: y, width: 2 * extent, height: period / 2))
            y += period
        }
        return ctx.makeImage()
    }

    /// Light-gray background sprinkled with black and white specks.
    static func speckles(size: Int = 400, seed: UInt64 = 7) -> CGImage? {
        guard let ctx = context(width: size, height: size) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        var rng = SeededGenerator(seed: seed)
        let speckSize = max(2, CGFloat(size) / 80)
        for _ in 0..<(size * size / 60) {
            let value: CGFloat = rng.unit() < 0.5 ? 0.05 : 0.97
            ctx.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
            ctx.fill(CGRect(
                x: CGFloat(rng.unit()) * CGFloat(size),
                y: CGFloat(rng.unit()) * CGFloat(size),
                width: speckSize, height: speckSize
            ))
        }
        return ctx.makeImage()
    }

    /// Black, smooth body with a few bright white reflections near the middle.
    static func glassyHighlights(size: Int = 400) -> CGImage? {
        guard let ctx = context(width: size, height: size) else { return nil }
        let s = CGFloat(size)
        ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for (x, y) in [(0.35, 0.4), (0.55, 0.6), (0.5, 0.35), (0.62, 0.48)] {
            ctx.fillEllipse(in: CGRect(x: s * x, y: s * y, width: s * 0.14, height: s * 0.035))
        }
        return ctx.makeImage()
    }

    /// Encodes an image as JPEG with an optional EXIF orientation.
    static func jpeg(_ image: CGImage, orientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
