import CoreGraphics
import Foundation

/// The math behind the "frame your rock" screen: a square frame on screen,
/// with the photo zoomed and panned underneath it.
///
/// A framing state is independent of the frame's on-screen size (so it
/// survives rotation):
/// * `zoom` 1 means the photo's shorter side exactly fills the frame;
/// * `offsetX`/`offsetY` are how far the photo's center sits from the frame's
///   center, in frame widths (positive = photo moved right/down).
///
/// Crop rectangles are in image pixels with a top-left origin, ready for
/// `CGImage.cropping(to:)`.
public struct CropFraming: Sendable, Equatable {
    public struct State: Sendable, Equatable {
        public var zoom: Double
        public var offsetX: Double
        public var offsetY: Double

        public init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
            self.zoom = zoom
            self.offsetX = offsetX
            self.offsetY = offsetY
        }
    }

    /// Zoomed all the way out: the photo's shorter side fills the frame,
    /// centered. The crop is then the photo's middle square.
    public static let zoomedOut = State()

    public let width: Double
    public let height: Double
    /// Largest allowed zoom, so the crop never gets smaller than
    /// `minimumCropSide` pixels (and never above `zoomLimit`).
    public let maxZoom: Double

    public init(width: Int, height: Int, minimumCropSide: Double = 160, zoomLimit: Double = 8) {
        self.width = Double(max(1, width))
        self.height = Double(max(1, height))
        let shortSide = min(self.width, self.height)
        self.maxZoom = max(1, min(zoomLimit, shortSide / minimumCropSide))
    }

    public var shortSide: Double { min(width, height) }

    /// Points per image pixel when the frame is `frameSide` points wide.
    public func displayScale(for state: State, frameSide: Double) -> Double {
        state.zoom * frameSide / shortSide
    }

    /// Keeps zoom within limits and the crop inside the photo.
    public func clamped(_ state: State) -> State {
        let zoom = min(maxZoom, max(1, state.zoom.isFinite ? state.zoom : 1))
        let limitX = (width * zoom / shortSide - 1) / 2
        let limitY = (height * zoom / shortSide - 1) / 2
        func clamp(_ value: Double, _ limit: Double) -> Double {
            value.isFinite ? min(limit, max(-limit, value)) : 0
        }
        return State(zoom: zoom, offsetX: clamp(state.offsetX, limitX), offsetY: clamp(state.offsetY, limitY))
    }

    /// Moves the photo by a drag, measured in frame widths.
    public func panned(_ state: State, byX dx: Double, y dy: Double) -> State {
        clamped(State(zoom: state.zoom, offsetX: state.offsetX + dx, offsetY: state.offsetY + dy))
    }

    /// Changes zoom while keeping the photo spot under an anchor fixed, as far
    /// as the photo's edges allow. The anchor is measured in frame widths from
    /// the frame's center (default: the middle of the frame); for a pinch it is
    /// where the fingers are.
    public func zoomed(_ state: State, to zoom: Double, aroundX anchorX: Double = 0, y anchorY: Double = 0) -> State {
        let current = clamped(state)
        let target = min(maxZoom, max(1, zoom.isFinite ? zoom : current.zoom))
        let ratio = target / current.zoom
        let ax = anchorX.isFinite ? anchorX : 0
        let ay = anchorY.isFinite ? anchorY : 0
        return clamped(State(
            zoom: target,
            offsetX: ax - (ax - current.offsetX) * ratio,
            offsetY: ay - (ay - current.offsetY) * ratio
        ))
    }

    /// The square of the photo inside the frame, in whole pixels.
    public func cropRect(for state: State) -> CGRect {
        let state = clamped(state)
        let side = min(shortSide, max(1, (shortSide / state.zoom).rounded()))
        let centerX = width / 2 - state.offsetX * shortSide / state.zoom
        let centerY = height / 2 - state.offsetY * shortSide / state.zoom
        let x = min(width - side, max(0, (centerX - side / 2).rounded()))
        let y = min(height - side, max(0, (centerY - side / 2).rounded()))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The framing that shows `rect` (pixels, top-left origin) as closely as
    /// the limits allow. Non-square rectangles are fitted by their longer side.
    public func state(showing rect: CGRect) -> State {
        let side = min(shortSide, max(1, Double(max(rect.width, rect.height))))
        let zoom = min(maxZoom, max(1, shortSide / side))
        let offsetX = (width / 2 - Double(rect.midX)) * zoom / shortSide
        let offsetY = (height / 2 - Double(rect.midY)) * zoom / shortSide
        return clamped(State(zoom: zoom, offsetX: offsetX, offsetY: offsetY))
    }

    /// A square around `box`, padded by `padding` × its longer side on every
    /// side, shrunk to fit and shifted (not shrunk further) to stay in the photo.
    public static func squareAround(_ box: CGRect, imageWidth: Int, imageHeight: Int, padding: Double = 0.15) -> CGRect {
        let width = Double(max(1, imageWidth))
        let height = Double(max(1, imageHeight))
        let longer = Double(max(box.width, box.height))
        let side = min(min(width, height), max(1, longer * (1 + 2 * padding)))
        let x = min(width - side, max(0, Double(box.midX) - side / 2))
        let y = min(height - side, max(0, Double(box.midY) - side / 2))
        return CGRect(x: x, y: y, width: side, height: side)
    }
}
