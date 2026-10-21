import Foundation
import Testing
@testable import RockKit

@Suite("Reference picture matcher (k-NN)")
struct ReferenceMatcherTests {
    let rockIDs = Fixtures.catalog.rocks.map(\.id)

    func samples() -> [ReferenceSample] {
        [
            ReferenceSample(rockID: "granite", vector: [1, 0, 0]),
            ReferenceSample(rockID: "granite", vector: [0.9, 0.1, 0]),
            ReferenceSample(rockID: "basalt", vector: [0, 1, 0]),
            ReferenceSample(rockID: "basalt", vector: [0.1, 0.9, 0]),
            ReferenceSample(rockID: "slate", vector: [0, 0, 1])
        ]
    }

    @Test("RM-01 an empty gallery gives no evidence")
    func emptyGallery() {
        let matcher = ReferenceMatcher(samples: [])
        #expect(matcher.isEmpty)
        #expect(matcher.evidence(for: [1, 0, 0], rockIDs: rockIDs) == nil)
    }

    @Test("RM-02 a query next to granite samples favours granite")
    func nearestIsGranite() throws {
        let matcher = ReferenceMatcher(samples: samples(), k: 3)
        let evidence = try #require(matcher.evidence(for: [0.95, 0.05, 0], rockIDs: rockIDs))
        let best = evidence.likelihoods.max { $0.value < $1.value }?.key
        #expect(best == "granite")
        #expect(matcher.nearestNeighbors(to: [0.95, 0.05, 0]).first?.rockID == "granite")
    }

    @Test("RM-03 k larger than the gallery uses every sample")
    func largeK() throws {
        let matcher = ReferenceMatcher(samples: samples(), k: 50)
        #expect(matcher.nearestNeighbors(to: [0, 0, 1]).count == 5)
        let evidence = try #require(matcher.evidence(for: [0, 0, 1], rockIDs: rockIDs))
        #expect(evidence.likelihoods.max { $0.value < $1.value }?.key == "slate")
    }

    @Test("RM-04 likelihoods are smoothed and sum to 1")
    func smoothing() throws {
        let matcher = ReferenceMatcher(samples: samples(), k: 3)
        let evidence = try #require(matcher.evidence(for: [1, 0, 0], rockIDs: rockIDs))
        #expect(evidence.likelihoods.count == rockIDs.count)
        #expect(evidence.likelihoods.values.allSatisfy { $0 > 0 })
        #expect(abs(evidence.likelihoods.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test("Vectors of the wrong length are ignored")
    func mismatchedLengths() {
        let matcher = ReferenceMatcher(samples: samples() + [ReferenceSample(rockID: "coal", vector: [1, 0])], k: 10)
        #expect(!matcher.nearestNeighbors(to: [1, 0, 0]).contains { $0.rockID == "coal" })
    }

    @Test("RM-05 Vision feature prints put look-alike textures closest together",
          .enabled(if: Fixtures.visionAvailable, "Vision feature prints are unavailable here"))
    func visionFeaturePrints() throws {
        let stripeRefs = try [0.0, 0.3, 1.4].map { angle in
            ReferenceSample(rockID: "shale", vector: try FeaturePrinter.vector(for: #require(TestImages.stripes(period: 20, angle: angle))))
        }
        let speckleRefs = try [11, 12, 13].map { seed in
            ReferenceSample(rockID: "granite", vector: try FeaturePrinter.vector(for: #require(TestImages.speckles(seed: UInt64(seed)))))
        }
        let matcher = ReferenceMatcher(samples: stripeRefs + speckleRefs, k: 3)

        let stripeQuery = try FeaturePrinter.vector(for: #require(TestImages.stripes(period: 28, angle: 0.8)))
        #expect(matcher.nearestNeighbors(to: stripeQuery).first?.rockID == "shale")

        let speckleQuery = try FeaturePrinter.vector(for: #require(TestImages.speckles(seed: 99)))
        #expect(matcher.nearestNeighbors(to: speckleQuery).first?.rockID == "granite")
    }

    @Test("The reference library loader reads <rock>/<picture> folders")
    func libraryLoader() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let graniteFolder = folder.appendingPathComponent("granite")
        let unknownFolder = folder.appendingPathComponent("kryptonite")
        try FileManager.default.createDirectory(at: graniteFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unknownFolder, withIntermediateDirectories: true)
        let image = try #require(TestImages.speckles(size: 128))
        try TestImages.jpeg(image).write(to: graniteFolder.appendingPathComponent("a.jpg"))
        try TestImages.jpeg(image).write(to: unknownFolder.appendingPathComponent("b.jpg"))
        try Data("not an image".utf8).write(to: graniteFolder.appendingPathComponent("notes.txt"))

        let samples = ReferenceLibrary.samples(in: folder, knownRockIDs: Set(rockIDs))
        if Fixtures.visionAvailable {
            #expect(samples.count == 1)
            #expect(samples.first?.rockID == "granite")
        } else {
            #expect(samples.isEmpty)
        }
        #expect(ReferenceLibrary.samples(in: folder.appendingPathComponent("missing"), knownRockIDs: []).isEmpty)
    }
}
