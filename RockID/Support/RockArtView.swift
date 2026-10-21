import RockKit
import SwiftUI
import UIKit

/// Caches rendered rock illustrations so lists stay smooth.
@MainActor
final class RockArtCache {
    static let shared = RockArtCache()
    private var images: [String: UIImage] = [:]

    func cached(_ rock: Rock, pixels: Int) -> UIImage? {
        images[key(rock, pixels)]
    }

    func image(for rock: Rock, pixels: Int) async -> UIImage? {
        if let image = cached(rock, pixels: pixels) { return image }
        let style = rock.art
        let rendered = await Task.detached(priority: .userInitiated) {
            RockArtRenderer.render(style, size: pixels)
        }.value
        guard let rendered else { return nil }
        let image = UIImage(cgImage: rendered)
        images[key(rock, pixels)] = image
        return image
    }

    private func key(_ rock: Rock, _ pixels: Int) -> String {
        "\(rock.id)-\(pixels)"
    }
}

/// The procedural illustration of a rock.
struct RockArtView: View {
    let rock: Rock
    var size: CGFloat
    @State private var loaded: (key: String, image: UIImage)?
    @Environment(\.displayScale) private var displayScale

    private var pixels: Int {
        // Bucket sizes so the cache is shared between similar views.
        let raw = Int(size * displayScale)
        return max(64, (raw + 63) / 64 * 64)
    }

    private var key: String { "\(rock.id)-\(pixels)" }

    private var image: UIImage? {
        RockArtCache.shared.cached(rock, pixels: pixels) ?? (loaded?.key == key ? loaded?.image : nil)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Circle()
                    .fill(Theme.softCard)
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Picture of \(rock.name)")
        .task(id: key) {
            let key = self.key
            if let image = await RockArtCache.shared.image(for: rock, pixels: pixels) {
                loaded = (key, image)
            }
        }
    }
}
