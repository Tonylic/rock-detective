import CoreGraphics
import Foundation
import Testing
@testable import RockKit

/// Timing budgets from the design doc. Debug builds are several times slower
/// than release builds, so passing here leaves plenty of headroom on device.
@Suite("Performance", .serialized)
struct PerformanceTests {
    func averageTime(iterations: Int, _ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<iterations { work() }
        }
        return elapsed / iterations
    }

    func fullEvidence() -> Evidence {
        var kid = SimulatedKid(rock: Fixtures.rock("schist"), seed: 3)
        var evidence = kid.answerEverything(catalog: Fixtures.catalog)
        evidence.photo = PhotoEvidence(beliefs: [
            .color: [.light: 0.2, .medium: 0.6, .dark: 0.2],
            .layers: [.yes: 0.8, .no: 0.2],
            .grains: [.yes: 0.7, .no: 0.3]
        ])
        return evidence
    }

    @Test("PF-01 scoring every rock with every clue takes under 1 ms")
    func scoring() {
        let evidence = fullEvidence()
        let matcher = Fixtures.matcher
        let average = averageTime(iterations: 1000) { _ = matcher.match(evidence) }
        print("PF-01 average \(average)")
        #expect(average < .milliseconds(1))
    }

    @Test("PF-02 planning the next question takes under 5 ms")
    func planning() {
        let planner = Fixtures.planner
        let evidence = Evidence(answers: [.color: .medium])
        let average = averageTime(iterations: 100) { _ = planner.suggestions(for: evidence) }
        print("PF-02 average \(average)")
        #expect(average < .milliseconds(5))
    }

    @Test("PF-03 analysing a photo takes under 150 ms")
    func photoAnalysis() throws {
        let image = try #require(RockArtRenderer.renderPracticePhoto(Fixtures.rock("granite").art, size: 2048))
        let analyzer = PhotoAnalyzer()
        _ = analyzer.analyze(image)
        let average = averageTime(iterations: 10) { _ = analyzer.analyze(image) }
        print("PF-03 average \(average)")
        #expect(average < .milliseconds(150))
    }

    @Test("PF-04 loading and downsampling a 4000×3000 photo takes under 300 ms")
    func loading() throws {
        let image = try #require(TestImages.speckles(size: 1000))
        let big = try #require(ImageLoader.redrawn(image, width: 4000, height: 3000))
        let data = TestImages.jpeg(big)
        let average = averageTime(iterations: 5) { _ = try? ImageLoader.image(from: data, maxPixelSize: 2048) }
        print("PF-04 average \(average)")
        #expect(average < .milliseconds(300))
    }
}
