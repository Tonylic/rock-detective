import CoreGraphics
import Foundation

public enum FeaturePrinterError: Error {
    case unavailable
    case noResult
}

#if canImport(Vision)
import Vision

/// Image embeddings from Apple's on-device Vision feature print network.
public enum FeaturePrinter {
    public static func vector(for image: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw FeaturePrinterError.noResult }
        let vector = observation.floatVector
        guard !vector.isEmpty else { throw FeaturePrinterError.noResult }
        return vector
    }
}

extension VNFeaturePrintObservation {
    var floatVector: [Float] {
        switch elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(elementCount)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(elementCount).map(Float.init) }
        default:
            return []
        }
    }
}
#else
public enum FeaturePrinter {
    public static func vector(for image: CGImage) throws -> [Float] {
        throw FeaturePrinterError.unavailable
    }
}
#endif

/// Loads a reference gallery laid out as `<folder>/<rockID>/<picture>` and
/// computes a feature print for each picture.
public enum ReferenceLibrary {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    public static func samples(in folder: URL, knownRockIDs: Set<String>) -> [ReferenceSample] {
        let fileManager = FileManager.default
        guard let rockFolders = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        var samples: [ReferenceSample] = []
        for rockFolder in rockFolders where knownRockIDs.contains(rockFolder.lastPathComponent) {
            let files = (try? fileManager.contentsOfDirectory(at: rockFolder, includingPropertiesForKeys: nil)) ?? []
            for file in files where imageExtensions.contains(file.pathExtension.lowercased()) {
                guard let data = try? Data(contentsOf: file),
                      let image = try? ImageLoader.image(from: data, maxPixelSize: 512),
                      let vector = try? FeaturePrinter.vector(for: image) else { continue }
                samples.append(ReferenceSample(rockID: rockFolder.lastPathComponent, vector: vector))
            }
        }
        return samples
    }
}
