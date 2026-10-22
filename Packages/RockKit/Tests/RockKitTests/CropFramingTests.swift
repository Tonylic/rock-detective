import CoreGraphics
import Foundation
import Testing
@testable import RockKit

@Suite("Photo cropping")
struct CropFramingTests {
    let landscape = CropFraming(width: 4000, height: 3000)

    func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    /// A big "table" photo with a rock drawn away from the middle.
    /// Returns the image and where the rock is (pixels, top-left origin).
    static func offCenterRockPhoto(_ rockID: String, width: Int = 1600, height: Int = 1000) -> (CGImage, CGRect)? {
        guard let ctx = TestImages.context(width: width, height: height),
              let rock = RockArtRenderer.render(Fixtures.rock(rockID).art, size: 420) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.79, green: 0.66, blue: 0.49, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let rockRect = CGRect(x: 120, y: 290, width: 420, height: 420)
        // Core Graphics draws bottom-up; flip the y for the top-left rectangle.
        ctx.draw(rock, in: CGRect(x: rockRect.minX, y: Double(height) - rockRect.maxY, width: 420, height: 420))
        guard let image = ctx.makeImage() else { return nil }
        return (image, rockRect)
    }

    @Test("CR-01 zoomed all the way out, the crop is the centered square of the shorter side")
    func fullFraming() {
        #expect(landscape.cropRect(for: CropFraming.zoomedOut) == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        let portrait = CropFraming(width: 3000, height: 4000)
        #expect(portrait.cropRect(for: CropFraming.zoomedOut) == CGRect(x: 0, y: 500, width: 3000, height: 3000))
        let square = CropFraming(width: 1200, height: 1200)
        #expect(square.cropRect(for: CropFraming.zoomedOut) == CGRect(x: 0, y: 0, width: 1200, height: 1200))
    }

    @Test("CR-02 panning stops at the photo's edges")
    func panningClamps() {
        let right = landscape.panned(CropFraming.zoomedOut, byX: 10, y: 0)
        #expect(landscape.cropRect(for: right).minX == 0)
        let left = landscape.panned(CropFraming.zoomedOut, byX: -10, y: 0)
        #expect(landscape.cropRect(for: left).maxX == 4000)
        // At zoom 1 a landscape photo has no room to move up or down.
        let down = landscape.panned(CropFraming.zoomedOut, byX: 0, y: 5)
        #expect(down.offsetY == 0)
        // Zoomed in, there is.
        let zoomed = landscape.zoomed(CropFraming.zoomedOut, to: 2)
        let up = landscape.panned(zoomed, byX: 0, y: -10)
        #expect(landscape.cropRect(for: up).maxY == 3000)
    }

    @Test("CR-03 zoom stays between 1 and the limit set by the minimum crop size")
    func zoomLimits() {
        #expect(landscape.maxZoom == 8)
        #expect(landscape.zoomed(CropFraming.zoomedOut, to: 100).zoom == 8)
        #expect(landscape.zoomed(CropFraming.zoomedOut, to: 0.1).zoom == 1)
        #expect(CropFraming(width: 400, height: 300).maxZoom == 300.0 / 160.0)
        #expect(CropFraming(width: 100, height: 100).maxZoom == 1)
        let maxCrop = landscape.cropRect(for: landscape.zoomed(CropFraming.zoomedOut, to: 100))
        #expect(maxCrop.width == 375)
    }

    @Test("CR-04 zooming keeps the same spot in the middle of the frame")
    func zoomKeepsCenter() {
        let panned = landscape.panned(CropFraming.zoomedOut, byX: -0.1, y: 0)
        let before = center(landscape.cropRect(for: panned))
        for zoom in [1.5, 2, 3.5, 6] {
            let after = center(landscape.cropRect(for: landscape.zoomed(panned, to: zoom)))
            #expect(abs(after.x - before.x) <= 1 && abs(after.y - before.y) <= 1, "zoom \(zoom)")
        }
    }

    @Test("CR-10 pinching zooms around the fingers")
    func anchoredZoom() {
        // A spot 0.3 frame widths right of center, on a photo zoomed in a little.
        let start = landscape.zoomed(CropFraming.zoomedOut, to: 1.5)
        let anchorX = 0.3, anchorY = -0.1
        func photoPoint(under x: Double, _ y: Double, in state: CropFraming.State) -> CGPoint {
            // Frame-width offset from the frame center → image pixels.
            let rect = landscape.cropRect(for: state)
            return CGPoint(x: Double(rect.midX) + x * Double(rect.width), y: Double(rect.midY) + y * Double(rect.width))
        }
        let before = photoPoint(under: anchorX, anchorY, in: start)
        let zoomed = landscape.zoomed(start, to: 3, aroundX: anchorX, y: anchorY)
        let after = photoPoint(under: anchorX, anchorY, in: zoomed)
        #expect(zoomed.zoom == 3)
        #expect(abs(after.x - before.x) <= 2 && abs(after.y - before.y) <= 2)
        // The default anchor is the frame's center (CR-04 behavior).
        #expect(landscape.zoomed(start, to: 3) == landscape.zoomed(start, to: 3, aroundX: 0, y: 0))
        // Bad anchors fall back to the center instead of breaking the framing.
        let bad = landscape.zoomed(start, to: 2, aroundX: .nan, y: .infinity)
        #expect(bad == landscape.zoomed(start, to: 2))
    }

    @Test("CR-05 a framing can be made to show a given square")
    func roundTrip() {
        let target = CGRect(x: 1200, y: 800, width: 1000, height: 1000)
        let shown = landscape.cropRect(for: landscape.state(showing: target))
        #expect(abs(shown.minX - target.minX) <= 1 && abs(shown.minY - target.minY) <= 1)
        #expect(abs(shown.width - target.width) <= 1)
        // Too small a square is limited by the maximum zoom, around the same center.
        let tiny = CGRect(x: 2000, y: 1500, width: 50, height: 50)
        let limited = landscape.cropRect(for: landscape.state(showing: tiny))
        #expect(limited.width == 375)
        #expect(abs(limited.midX - tiny.midX) <= 1 && abs(limited.midY - tiny.midY) <= 1)
    }

    @Test("CR-06 a suggested square pads the object and stays inside the photo")
    func squareAround() {
        let square = CropFraming.squareAround(CGRect(x: 100, y: 100, width: 200, height: 100), imageWidth: 4000, imageHeight: 3000)
        #expect(square == CGRect(x: 70, y: 20, width: 260, height: 260))
        let corner = CropFraming.squareAround(CGRect(x: 0, y: 0, width: 100, height: 100), imageWidth: 4000, imageHeight: 3000)
        #expect(corner.minX == 0 && corner.minY == 0 && corner.width == 130)
        let huge = CropFraming.squareAround(CGRect(x: 0, y: 0, width: 4000, height: 3000), imageWidth: 4000, imageHeight: 3000)
        #expect(huge == CGRect(x: 500, y: 0, width: 3000, height: 3000))
    }

    @Test("CR-07 every framing gives a whole-pixel square inside the photo")
    func cropAlwaysValid() {
        var rng = SeededGenerator(seed: 2024)
        for _ in 0..<2000 {
            let framing = CropFraming(width: 1 + Int(rng.unit() * 5000), height: 1 + Int(rng.unit() * 5000))
            var state = CropFraming.State(
                zoom: rng.range(-2...20),
                offsetX: rng.range(-3...3),
                offsetY: rng.range(-3...3)
            )
            if rng.unit() < 0.05 { state.zoom = .nan }
            let rect = framing.cropRect(for: state)
            #expect(rect.width == rect.height)
            #expect(rect.minX >= 0 && rect.minY >= 0)
            #expect(Double(rect.maxX) <= framing.width && Double(rect.maxY) <= framing.height)
            #expect(rect.minX == rect.minX.rounded() && rect.width == rect.width.rounded())
            #expect(rect.minY == rect.minY.rounded() && rect.height == rect.height.rounded())
            #expect(Double(rect.width) >= (framing.shortSide / framing.maxZoom).rounded(.down) - 1)
        }
    }

    @Test("Vision rectangles convert to top-left pixel coordinates")
    func pixelRect() {
        let rect = SubjectFinder.pixelRect(fromNormalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), width: 400, height: 200)
        #expect(rect == CGRect(x: 100, y: 50, width: 200, height: 50))
    }

    @Test("CR-08 the subject finder centers an off-center rock",
          .enabled(if: Fixtures.subjectFinderAvailable, "Vision saliency is unavailable here"))
    func subjectFinder() throws {
        let (photo, rockRect) = try #require(Self.offCenterRockPhoto("basalt"))
        let crop = try #require(SubjectFinder.suggestedCrop(for: photo))
        #expect(crop.contains(CGPoint(x: rockRect.midX, y: rockRect.midY)))
        #expect(abs(crop.midX - rockRect.midX) < 120 && abs(crop.midY - rockRect.midY) < 120)
        #expect(crop.width < 0.8 * Double(photo.height))
    }

    @Test("CR-09 cropping to an off-center rock improves its identification", arguments: ["granite", "basalt", "gneiss"])
    func croppingHelps(rockID: String) throws {
        let (photo, rockRect) = try #require(Self.offCenterRockPhoto(rockID))
        let framing = CropFraming(width: photo.width, height: photo.height)
        let crop = framing.cropRect(for: framing.state(showing: rockRect))
        let cropped = try #require(photo.cropping(to: crop))

        let analyzer = PhotoAnalyzer()
        let uncroppedRank = Fixtures.matcher.match(Evidence(photo: analyzer.analyze(photo))).rank(of: rockID) ?? 99
        let croppedRank = Fixtures.matcher.match(Evidence(photo: analyzer.analyze(cropped))).rank(of: rockID) ?? 99
        print("CR-09 \(rockID): uncropped rank \(uncroppedRank), cropped rank \(croppedRank)")
        #expect(croppedRank <= 3)
        #expect(croppedRank < uncroppedRank)
    }
}
