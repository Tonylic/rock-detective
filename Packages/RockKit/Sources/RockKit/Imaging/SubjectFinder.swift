import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision
#endif

/// Finds the main object in a photo (usually the rock) with Apple's on-device
/// objectness saliency, so the crop screen can start centered on it.
public enum SubjectFinder {
    /// Bounding box of the most prominent object, in pixels with a top-left
    /// origin, or `nil` when Vision finds nothing (or isn't available).
    public static func subjectBounds(in image: CGImage) -> CGRect? {
        #if canImport(Vision)
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let objects = request.results?.first?.salientObjects,
              let largest = objects.max(by: { area($0.boundingBox) < area($1.boundingBox) }) else {
            return nil
        }
        return pixelRect(fromNormalized: largest.boundingBox, width: image.width, height: image.height)
        #else
        return nil
        #endif
    }

    /// A padded square crop around the main object, or `nil` if none was found.
    public static func suggestedCrop(for image: CGImage, padding: Double = 0.15) -> CGRect? {
        guard let bounds = subjectBounds(in: image), bounds.width >= 1, bounds.height >= 1 else { return nil }
        return CropFraming.squareAround(bounds, imageWidth: image.width, imageHeight: image.height, padding: padding)
    }

    /// Converts a Vision rectangle (normalized, bottom-left origin) to pixels
    /// with a top-left origin.
    static func pixelRect(fromNormalized box: CGRect, width: Int, height: Int) -> CGRect {
        let w = Double(width)
        let h = Double(height)
        return CGRect(
            x: Double(box.minX) * w,
            y: (1 - Double(box.maxY)) * h,
            width: Double(box.width) * w,
            height: Double(box.height) * h
        )
    }

    private static func area(_ rect: CGRect) -> Double {
        Double(rect.width * rect.height)
    }
}
