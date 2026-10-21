import CoreGraphics
import Foundation

/// Reads geologically meaningful visual clues from a photo:
///
/// * **Color tone** (median brightness): light felsic rocks vs dark mafic rocks.
/// * **Warm hue**: pink feldspar, red iron oxide.
/// * **Grain** (fine-scale texture energy): visible crystals or sand grains.
/// * **Speckles** (pixels standing out from their neighbourhood): salt-and-pepper.
/// * **Layers** (block-normalised structure-tensor coherence): bedding, foliation, banding.
/// * **Glassy shine** (small colourless highlights on a smooth body).
///
/// Only the central part of the photo is analysed, where kids put the rock.
/// The output is soft evidence: every belief stays between 0.2 and 0.8.
public struct PhotoAnalyzer: Sendable {
    public var workingSize: Int
    public var cropFraction: Double
    public var minimumInputSize: Int

    public init(workingSize: Int = 160, cropFraction: Double = 0.6, minimumInputSize: Int = 16) {
        self.workingSize = workingSize
        self.cropFraction = cropFraction
        self.minimumInputSize = minimumInputSize
    }

    public func analyze(_ image: CGImage) -> PhotoEvidence {
        guard let features = features(of: image) else { return .none }
        return PhotoEvidence(features: features, beliefs: Self.beliefs(from: features))
    }

    // MARK: - Features

    public func features(of image: CGImage) -> PhotoFeatures? {
        guard image.width >= minimumInputSize, image.height >= minimumInputSize,
              let pixels = samplePixels(of: image) else { return nil }
        let n = workingSize
        let count = n * n

        var luma = [Float](repeating: 0, count: count)
        var warmCount = 0
        var saturation = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let r = Float(pixels[i * 4]) / 255
            let g = Float(pixels[i * 4 + 1]) / 255
            let b = Float(pixels[i * 4 + 2]) / 255
            luma[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let s = maxValue > 0 ? (maxValue - minValue) / maxValue : 0
            saturation[i] = s
            if s >= 0.27, maxValue >= 0.25 {
                let hue = Self.hueDegrees(r: r, g: g, b: b, maxValue: maxValue, minValue: minValue)
                if hue < 45 || hue >= 330 { warmCount += 1 }
            }
        }

        let median = Double(luma.sorted()[count / 2])

        // Glare: bright, colourless spots well above a darker body. On light
        // rocks white minerals look the same as glare, so glare isn't measured there.
        let highlightThreshold = Float(max(0.85, median + 0.35))
        var highlightMask = [Float](repeating: 0, count: count)
        var highlights = 0
        if median < Self.glareBodyLimit {
            for i in 0..<count where luma[i] >= highlightThreshold && saturation[i] <= 0.25 {
                highlightMask[i] = 1
                highlights += 1
            }
        }
        let nearHighlight = Self.boxMean(highlightMask, width: n, height: n, radius: 4)

        // Grain: average local contrast (standard deviation in 5×5 windows).
        let squares = luma.map { $0 * $0 }
        let mean5 = Self.boxMean(luma, width: n, height: n, radius: 2)
        let meanSquares5 = Self.boxMean(squares, width: n, height: n, radius: 2)
        var texture = 0.0
        var counted = 0
        for i in 0..<count where nearHighlight[i] == 0 {
            texture += Double(max(0, meanSquares5[i] - mean5[i] * mean5[i]).squareRoot())
            counted += 1
        }
        texture = counted > 0 ? texture / Double(counted) : 0

        // Specks: pixels that stand out from their 9×9 neighbourhood, ignoring glare.
        let local9 = Self.boxMean(luma, width: n, height: n, radius: 4)
        var speckles = 0
        for i in 0..<count where nearHighlight[i] == 0 && abs(luma[i] - local9[i]) > 0.15 {
            speckles += 1
        }

        return PhotoFeatures(
            medianLuminance: median,
            warmFraction: Double(warmCount) / Double(count),
            textureEnergy: texture,
            speckleFraction: Double(speckles) / Double(count),
            orientationCoherence: Self.orientationCoherence(luma, size: n, ignoring: nearHighlight),
            specularFraction: Double(highlights) / Double(count)
        )
    }

    /// Central square crop drawn into an RGBX buffer of `workingSize`².
    private func samplePixels(of image: CGImage) -> [UInt8]? {
        let side = max(1, Int(Double(min(image.width, image.height)) * cropFraction))
        let crop = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        )
        let source = image.cropping(to: crop) ?? image
        let n = workingSize
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: n,
                height: n,
                bitsPerComponent: 8,
                bytesPerRow: n * 4,
                space: ImageLoader.sRGB,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: n, height: n)
            context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(rect)
            context.interpolationQuality = .medium
            context.draw(source, in: rect)
            return true
        }
        return drawn ? pixels : nil
    }

    static func hueDegrees(r: Float, g: Float, b: Float, maxValue: Float, minValue: Float) -> Float {
        let delta = maxValue - minValue
        guard delta > 0 else { return 0 }
        var hue: Float
        if maxValue == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return hue
    }

    /// Mean over a (2r+1)² window (clipped at the borders), via an integral image.
    static func boxMean(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let stride = width + 1
        var integral = [Double](repeating: 0, count: stride * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            for x in 0..<width {
                rowSum += Double(values[y * width + x])
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum
            }
        }
        var output = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius)
            let y1 = min(height - 1, y + radius)
            for x in 0..<width {
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                let sum = integral[(y1 + 1) * stride + x1 + 1] - integral[y0 * stride + x1 + 1]
                    - integral[(y1 + 1) * stride + x0] + integral[y0 * stride + x0]
                output[y * width + x] = Float(sum / Double((y1 - y0 + 1) * (x1 - x0 + 1)))
            }
        }
        return output
    }

    /// How consistently edges point the same way, 0 … 1. Each block of the image
    /// contributes one normalised structure tensor (flat blocks count as
    /// direction-less), so one strong edge can't dominate but stripes
    /// running through the whole picture do.
    static func orientationCoherence(
        _ luma: [Float],
        size n: Int,
        ignoring mask: [Float]? = nil,
        blocks: Int = 4,
        flatEnergy: Double = 4e-4
    ) -> Double {
        let smooth = boxMean(luma, width: n, height: n, radius: 2)
        let blockSize = max(1, n / blocks)
        var sxx = 0.0, syy = 0.0, sxy = 0.0

        for by in 0..<blocks {
            for bx in 0..<blocks {
                var jxx = 0.0, jyy = 0.0, jxy = 0.0
                var count = 0
                let yRange = max(1, by * blockSize)..<min(n - 1, (by + 1) * blockSize)
                let xRange = max(1, bx * blockSize)..<min(n - 1, (bx + 1) * blockSize)
                guard !yRange.isEmpty, !xRange.isEmpty else { continue }
                for y in yRange {
                    let up = (y - 1) * n, row = y * n, down = (y + 1) * n
                    for x in xRange {
                        if let mask, mask[row + x] > 0 { continue }
                        let gx = Double(
                            (smooth[up + x + 1] + 2 * smooth[row + x + 1] + smooth[down + x + 1])
                                - (smooth[up + x - 1] + 2 * smooth[row + x - 1] + smooth[down + x - 1])
                        )
                        let gy = Double(
                            (smooth[down + x - 1] + 2 * smooth[down + x] + smooth[down + x + 1])
                                - (smooth[up + x - 1] + 2 * smooth[up + x] + smooth[up + x + 1])
                        )
                        jxx += gx * gx
                        jyy += gy * gy
                        jxy += gx * gy
                        count += 1
                    }
                }
                let trace = jxx + jyy
                if count == 0 || trace / Double(count) < flatEnergy {
                    sxx += 0.5
                    syy += 0.5
                } else {
                    sxx += jxx / trace
                    syy += jyy / trace
                    sxy += jxy / trace
                }
            }
        }
        let total = sxx + syy
        guard total > 0 else { return 0 }
        return min(1, ((sxx - syy) * (sxx - syy) + 4 * sxy * sxy).squareRoot() / total)
    }

    // MARK: - Beliefs

    /// Glare is only measured when the rock's median brightness is below this.
    static let glareBodyLimit = 0.45

    static let minimumBelief = 0.2
    static let maximumBelief = 0.8

    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    static func soft(_ p: Double) -> Double {
        min(maximumBelief, max(minimumBelief, p))
    }

    static func yesNo(_ p: Double) -> [Answer: Double] {
        let yes = soft(p)
        return [.yes: yes, .no: 1 - yes]
    }

    /// Converts measured features into soft beliefs about clue answers.
    public static func beliefs(from f: PhotoFeatures) -> [ClueID: [Answer: Double]] {
        let dark = logistic((0.30 - f.medianLuminance) / 0.04)
        let light = logistic((f.medianLuminance - 0.62) / 0.04)
        let medium = max(0, 1 - dark - light)
        // Blend with a uniform guess so color is never certain from a photo alone.
        let blended = [Answer.light: light, .medium: medium, .dark: dark].mapValues { 0.1 + 0.7 * $0 }
        let total = blended.values.reduce(0, +)

        // Layers make contrast too, but it's lined up; grains make contrast in every direction.
        let isotropicTexture = f.textureEnergy * (1 - 0.8 * f.orientationCoherence)
        let grains = logistic((isotropicTexture - 0.025) / 0.007)
        let speckled = logistic((f.speckleFraction - 0.04) / 0.012)
        let layers = logistic((f.orientationCoherence - 0.38) / 0.07)
        let reddish = logistic((f.warmFraction - 0.3) / 0.08)
        let shine = logistic((f.specularFraction - 0.01) / 0.004)
        let roughness = logistic((f.textureEnergy - 0.05) / 0.01)
        // Missing highlights are weak evidence (diffuse light hides shine), so
        // the "not glassy" side stays close to neutral.
        let glassy = 0.35 + 0.45 * shine * (1 - 0.6 * roughness)

        return [
            .color: blended.mapValues { $0 / total },
            .grains: yesNo(grains),
            .speckled: yesNo(speckled),
            .layers: yesNo(layers),
            .reddish: yesNo(reddish),
            .glassy: yesNo(glassy)
        ]
    }
}
