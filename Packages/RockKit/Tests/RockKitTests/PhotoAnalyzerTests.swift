import CoreGraphics
import Foundation
import Testing
@testable import RockKit

@Suite("Photo analysis")
struct PhotoAnalyzerTests {
    let analyzer = PhotoAnalyzer()

    func evidence(_ image: CGImage?) throws -> PhotoEvidence {
        let image = try #require(image)
        return analyzer.analyze(image)
    }

    func yes(_ evidence: PhotoEvidence, _ clue: ClueID) -> Double {
        evidence.belief(.yes, for: clue) ?? -1
    }

    func dominantTone(_ evidence: PhotoEvidence) -> Answer? {
        evidence.beliefs[.color]?.max { $0.value < $1.value }?.key
    }

    @Test("IA-01 uniform dark gray reads as dark, fine-grained, unlayered")
    func uniformDark() throws {
        let e = try evidence(TestImages.gray(0.15))
        #expect(dominantTone(e) == .dark)
        #expect(yes(e, .grains) <= 0.25)
        #expect(yes(e, .layers) <= 0.25)
        #expect(yes(e, .speckled) <= 0.25)
    }

    @Test("IA-02 near-white reads as light")
    func uniformLight() throws {
        let e = try evidence(TestImages.gray(0.9))
        #expect(dominantTone(e) == .light)
        let e2 = try evidence(TestImages.gray(0.47))
        #expect(dominantTone(e2) == .medium)
    }

    @Test("IA-03 horizontal stripes read as layers")
    func horizontalStripes() throws {
        let e = try evidence(TestImages.stripes(angle: 0))
        #expect(yes(e, .layers) >= 0.7)
        #expect((e.features?.orientationCoherence ?? 0) > 0.8)
    }

    @Test("IA-04 layers are detected at any angle", arguments: [0.4, 0.785, 1.2, 1.5708])
    func rotatedStripes(angle: Double) throws {
        let e = try evidence(TestImages.stripes(angle: CGFloat(angle)))
        #expect(yes(e, .layers) >= 0.7, "angle \(angle)")
    }

    @Test("IA-05 salt-and-pepper speckles read as grains and specks, not layers")
    func speckles() throws {
        let e = try evidence(TestImages.speckles())
        #expect(yes(e, .speckled) >= 0.7)
        #expect(yes(e, .grains) >= 0.7)
        #expect(yes(e, .layers) <= 0.3)
    }

    @Test("IA-06 bright highlights on a dark smooth body read as glassy")
    func glassy() throws {
        let e = try evidence(TestImages.glassyHighlights())
        #expect(yes(e, .glassy) >= 0.7)
        #expect(dominantTone(e) == .dark)
        let matte = try evidence(TestImages.gray(0.15))
        #expect(yes(matte, .glassy) < 0.5)
    }

    @Test("IA-07 warm colors read as reddish; gray does not")
    func reddish() throws {
        let warm = try evidence(TestImages.uniform(red: 0.85, green: 0.4, blue: 0.3))
        #expect(yes(warm, .reddish) >= 0.7)
        let gray = try evidence(TestImages.gray(0.5))
        #expect(yes(gray, .reddish) <= 0.25)
        let blue = try evidence(TestImages.uniform(red: 0.2, green: 0.4, blue: 0.85))
        #expect(yes(blue, .reddish) <= 0.25)
    }

    @Test("IA-08 tiny images give neutral evidence without crashing", arguments: [1, 3, 15])
    func tinyImages(size: Int) throws {
        let e = try evidence(TestImages.gray(0.5, size: size))
        #expect(e.isEmpty)
        #expect(e.spottedClues.isEmpty)
    }

    @Test("IA-09 yes/no beliefs stay soft and color beliefs sum to 1")
    func beliefsStaySoft() throws {
        let images = [
            TestImages.gray(0.02), TestImages.gray(0.98), TestImages.stripes(), TestImages.speckles(),
            TestImages.glassyHighlights(), TestImages.uniform(red: 1, green: 0, blue: 0)
        ]
        for image in images {
            let e = try evidence(image)
            for (clue, beliefs) in e.beliefs {
                let total = beliefs.values.reduce(0, +)
                #expect(abs(total - 1) < 1e-9, "\(clue)")
                if clue == .color {
                    #expect(beliefs.values.allSatisfy { $0 > 0.05 && $0 < 0.85 })
                } else {
                    #expect(beliefs.values.allSatisfy { $0 >= 0.2 - 1e-9 && $0 <= 0.8 + 1e-9 }, "\(clue)")
                }
            }
        }
    }

    @Test("IA-10 procedural art of a rock ranks that rock highly from the photo alone",
          arguments: ["granite", "basalt", "gneiss", "obsidian", "marble", "slate"])
    func artRecognition(rockID: String) throws {
        let rock = Fixtures.rock(rockID)
        let image = try #require(RockArtRenderer.renderTexture(rock.art, size: 512))
        let e = analyzer.analyze(image)
        let result = Fixtures.matcher.match(Evidence(photo: e))
        let rank = result.rank(of: rockID) ?? 99
        #expect(rank <= 5, "\(rockID) rank \(rank); top: \(result.top(5).map(\.rockID)); features: \(String(describing: e.features))")
    }

    @Test("IA-14 practice photos of every rock give a sensible photo-only ranking")
    func practicePhotos() throws {
        // A regression guard on the app's own illustrations, not a real-world accuracy claim.
        var top3 = 0
        var top5 = 0
        for rock in Fixtures.catalog.rocks {
            let image = try #require(RockArtRenderer.renderPracticePhoto(rock.art, size: 1200))
            let rank = Fixtures.matcher.match(Evidence(photo: analyzer.analyze(image))).rank(of: rock.id) ?? 99
            if rank <= 3 { top3 += 1 }
            if rank <= 5 { top5 += 1 }
        }
        print("IA-14 photo-only top-3 \(top3)/24, top-5 \(top5)/24")
        #expect(top5 >= 18)
        #expect(top3 >= 12)

        let granite = try #require(RockArtRenderer.renderPracticePhoto(Fixtures.rock("granite").art, size: 1200))
        let evidence = analyzer.analyze(granite)
        #expect(Fixtures.matcher.match(Evidence(photo: evidence)).best.rockID == "granite")
        #expect(evidence.spottedClues.contains { $0.id == "speckled" })
        #expect(!evidence.spottedClues.contains { $0.id == "fine" })
    }

    @Test("IA-15 layers are not mistaken for grains, and white specks are not glare")
    func confounds() throws {
        let stripes = try evidence(TestImages.stripes())
        #expect(yes(stripes, .grains) <= 0.35)
        let speckles = try evidence(TestImages.speckles())
        #expect(yes(speckles, .glassy) < 0.5)
        #expect((speckles.features?.specularFraction ?? 1) == 0)
    }

    @Test("IA-11 the loader downsamples large photos and keeps the aspect ratio")
    func downsampling() throws {
        let big = try #require(TestImages.uniform(red: 0.5, green: 0.4, blue: 0.3, width: 4000, height: 3000))
        let data = TestImages.jpeg(big)
        let loaded = try ImageLoader.image(from: data, maxPixelSize: 1024)
        #expect(loaded.width == 1024)
        #expect(loaded.height == 768)

        let small = try ImageLoader.image(from: TestImages.jpeg(try #require(TestImages.gray(0.5, size: 300))), maxPixelSize: 2048)
        #expect(small.width == 300 && small.height == 300)
    }

    @Test("IA-12 the loader applies EXIF orientation")
    func orientation() throws {
        let landscape = try #require(TestImages.uniform(red: 0.2, green: 0.6, blue: 0.4, width: 400, height: 200))
        let rotated = try ImageLoader.image(from: TestImages.jpeg(landscape, orientation: 6), maxPixelSize: 2048)
        #expect(rotated.width == 200)
        #expect(rotated.height == 400)
    }

    @Test("IA-13 invalid image data throws")
    func invalidData() {
        #expect(throws: ImageLoaderError.unreadable) { try ImageLoader.image(from: Data("nope".utf8)) }
        #expect(throws: ImageLoaderError.unreadable) { try ImageLoader.image(from: Data()) }
    }

    @Test("Spotted clues describe strong photo evidence")
    func spottedClues() throws {
        let stripes = try evidence(TestImages.stripes())
        #expect(stripes.spottedClues.contains { $0.clue == .layers })
        let dark = try evidence(TestImages.gray(0.1))
        #expect(dark.spottedClues.contains { $0.id == "dark" })
        #expect(dark.spottedClues.contains { $0.id == "fine" })
    }

    @Test("IA-16 photo suggestions only appear for clear evidence")
    func suggestions() throws {
        let stripes = try evidence(TestImages.stripes())
        #expect(stripes.suggestedAnswer(for: .layers) == .yes)
        #expect(stripes.suggestedAnswer(for: .fizz) == nil)
        let dark = try evidence(TestImages.gray(0.1))
        #expect(dark.suggestedAnswer(for: .color) == .dark)
        #expect(dark.suggestedAnswer(for: .grains) == .no)
        #expect(PhotoEvidence.none.suggestedAnswer(for: .layers) == nil)
    }

    @Test("Every rock's art renders at several sizes")
    func artRenders() {
        for rock in Fixtures.catalog.rocks {
            for size in [64, 256] {
                let image = RockArtRenderer.render(rock.art, size: size)
                #expect(image?.width == size, "\(rock.id)")
            }
            #expect(RockArtRenderer.renderPracticePhoto(rock.art, size: 300) != nil)
        }
        #expect(RockArtRenderer.render(Fixtures.rock("granite").art, size: 0) == nil)
    }

    @Test("JPEG encoding downsizes and flattens transparency")
    func jpegEncoding() throws {
        let art = try #require(RockArtRenderer.render(Fixtures.rock("granite").art, size: 1500))
        let data = try ImageLoader.jpegData(from: art, maxPixelSize: 500)
        let decoded = try ImageLoader.image(from: data)
        #expect(max(decoded.width, decoded.height) == 500)
    }
}
