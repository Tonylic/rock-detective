import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoaderError: Error, Equatable {
    case unreadable
    case encodingFailed
}

/// Decoding, downsampling and encoding of photos using ImageIO.
public enum ImageLoader {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Decodes image data, applies its EXIF orientation, and downsamples so the
    /// longest side is at most `maxPixelSize`. Never upscales.
    public static func image(from data: Data, maxPixelSize: Int = 2048) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageLoaderError.unreadable
        }
        var limit = maxPixelSize
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            limit = min(maxPixelSize, max(width, height))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, limit)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoaderError.unreadable
        }
        return image
    }

    /// Returns `image` scaled so its longest side is at most `maxPixelSize`.
    /// Transparent areas become white.
    public static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        return redrawn(image, width: width, height: height) ?? image
    }

    static func redrawn(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// JPEG-encodes `image`, first downscaling it to `maxPixelSize`.
    public static func jpegData(from image: CGImage, maxPixelSize: Int = 1024, quality: Double = 0.8) throws -> Data {
        var scaled = downscaled(image, maxPixelSize: maxPixelSize)
        if scaled.alphaInfo != .none, scaled.alphaInfo != .noneSkipLast, scaled.alphaInfo != .noneSkipFirst,
           let opaque = redrawn(scaled, width: scaled.width, height: scaled.height) {
            scaled = opaque
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageLoaderError.encodingFailed
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, properties)
        guard CGImageDestinationFinalize(destination) else { throw ImageLoaderError.encodingFailed }
        return data as Data
    }

    /// PNG-encodes `image` (used for tests and procedural art).
    public static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageLoaderError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageLoaderError.encodingFailed }
        return data as Data
    }
}
