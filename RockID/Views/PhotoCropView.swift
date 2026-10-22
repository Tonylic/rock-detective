import RockKit
import SwiftUI

/// "Frame your rock": the photo sits under a square frame; kids pinch and drag
/// until the rock fills it. When Vision can find the rock, the screen starts
/// already centered on it.
struct PhotoCropView: View {
    let photo: CGImage
    let onUse: (CGImage) -> Void
    let onCancel: () -> Void

    private let framing: CropFraming
    @State private var state = CropFraming.zoomedOut
    @State private var suggestion: CropFraming.State?
    @State private var isSearching = true
    /// The kid has chosen a framing themselves (gesture, button, or VoiceOver),
    /// so a late Vision suggestion must not move the photo.
    @State private var userAdjusted = false
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    /// True while a pinch or drag is in progress. SwiftUI resets it when the
    /// gesture ends *or is cancelled*, which `onEnded` alone doesn't cover.
    @GestureState private var isGesturing = false
    @State private var headerHeight: CGFloat = 130
    @State private var controlsHeight: CGFloat = 180
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(photo: CGImage, onUse: @escaping (CGImage) -> Void, onCancel: @escaping () -> Void) {
        self.photo = photo
        self.onUse = onUse
        self.onCancel = onCancel
        self.framing = CropFraming(width: photo.width, height: photo.height)
    }

    /// Where the square frame sits, between the measured header and controls.
    private struct FrameLayout {
        let size: CGSize
        let side: CGFloat
        let center: CGPoint

        init(size: CGSize, top: CGFloat, bottom: CGFloat) {
            self.size = size
            let available = max(0, size.height - top - bottom)
            side = max(0, min(size.width - 48, available - 24))
            center = CGPoint(x: size.width / 2, y: top + available / 2)
        }

        var frameRect: CGRect {
            CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }

        /// A point on screen as frame widths from the frame's center.
        func frameUnits(_ point: CGPoint) -> (x: Double, y: Double) {
            guard side > 0 else { return (0, 0) }
            return ((point.x - center.x) / side, (point.y - center.y) / side)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = FrameLayout(size: geometry.size, top: headerHeight, bottom: controlsHeight)
            ZStack {
                photoLayer(layout)
                dimming(layout)
                frameOutline(layout)
                touchLayer(layout)
                VStack(spacing: 0) {
                    header
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    Spacer(minLength: 0)
                    controls
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        // A containing element keeps the buttons' own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cropView")
        .task { await findRock() }
    }

    // MARK: - Layers

    private func photoLayer(_ layout: FrameLayout) -> some View {
        let scale = framing.displayScale(for: state, frameSide: layout.side)
        return Image(decorative: photo, scale: 1)
            .resizable()
            .interpolation(.medium)
            .frame(width: framing.width * scale, height: framing.height * scale)
            .position(
                x: layout.center.x + state.offsetX * layout.side,
                y: layout.center.y + state.offsetY * layout.side
            )
            .accessibilityHidden(true)
    }

    private func dimming(_ layout: FrameLayout) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: layout.size).insetBy(dx: -400, dy: -400))
            path.addRoundedRect(in: layout.frameRect, cornerSize: CGSize(width: 24, height: 24))
        }
        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func frameOutline(_ layout: FrameLayout) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white, lineWidth: 4)
            // The middle of the frame is where the photo clues look most closely.
            Circle()
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
                .padding(layout.side * 0.2)
        }
        .frame(width: layout.side, height: layout.side)
        .position(layout.center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Catches pinches and drags anywhere outside the header and buttons.
    private func touchLayer(_ layout: FrameLayout) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                dragGesture(layout)
                    .simultaneously(with: magnifyGesture(layout))
                    .updating($isGesturing) { _, active, _ in active = true }
            )
            .onChange(of: isGesturing) { _, active in
                // Runs on normal ends and on cancellation alike.
                if !active {
                    lastTranslation = .zero
                    lastMagnification = 1
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Your photo")
            .accessibilityValue("Zoom \(Int((state.zoom * 100).rounded())) percent")
            .accessibilityHint("Swipe up or down to zoom. Use the actions to see more of each side.")
            .accessibilityAdjustableAction { direction in
                userAdjusted = true
                switch direction {
                case .increment: state = framing.zoomed(state, to: state.zoom * 1.25)
                case .decrement: state = framing.zoomed(state, to: state.zoom / 1.25)
                @unknown default: break
                }
            }
            // Moving the photo right shows more of its left side, and so on.
            .accessibilityAction(named: "Show more on the left") { nudge(x: 0.15, y: 0) }
            .accessibilityAction(named: "Show more on the right") { nudge(x: -0.15, y: 0) }
            .accessibilityAction(named: "Show more at the top") { nudge(x: 0, y: 0.15) }
            .accessibilityAction(named: "Show more at the bottom") { nudge(x: 0, y: -0.15) }
            .accessibilityIdentifier("cropArea")
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Frame your rock 🎯")
                .font(Theme.rounded(34, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(hint)
                .font(Theme.rounded(19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("cropHint")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var hint: String {
        if let suggestion, state == suggestion {
            return "✨ I found your rock! Pinch and drag to fix it if needed."
        }
        if isSearching && !userAdjusted { return "Looking for your rock…" }
        return "Pinch to zoom and drag until your rock fills the circle."
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 14) {
                HStack(spacing: 14) { toolButtons(fontSize: 19) }
                HStack(spacing: 16) {
                    cancelButton(fontSize: 21)
                    useButton(fontSize: 23)
                }
            }
            // Narrow windows (Slide Over, Split View): stack the main buttons.
            VStack(spacing: 10) {
                HStack(spacing: 10) { toolButtons(fontSize: 16) }
                useButton(fontSize: 20)
                cancelButton(fontSize: 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func toolButtons(fontSize: CGFloat) -> some View {
        if let suggestion {
            Button {
                userAdjusted = true
                withAnimation(animation) { state = suggestion }
            } label: {
                Label("Center rock", systemImage: "scope")
                    .font(Theme.rounded(fontSize, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.grape))
            .accessibilityIdentifier("centerRockButton")
        }
        Button {
            userAdjusted = true
            withAnimation(animation) { state = CropFraming.zoomedOut }
        } label: {
            Label("Zoom out", systemImage: "arrow.down.right.and.arrow.up.left")
                .font(Theme.rounded(fontSize, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .buttonStyle(ChunkyButtonStyle(color: Color(white: 0.32)))
        .accessibilityIdentifier("zoomOutButton")
    }

    private func cancelButton(fontSize: CGFloat) -> some View {
        Button(action: onCancel) {
            Label("Cancel", systemImage: "xmark")
                .font(Theme.rounded(fontSize, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .buttonStyle(ChunkyButtonStyle(color: Color(white: 0.32)))
        .accessibilityIdentifier("cancelCropButton")
    }

    private func useButton(fontSize: CGFloat) -> some View {
        Button(action: useFramedPhoto) {
            Label("Use this photo", systemImage: "checkmark.circle.fill")
                .font(Theme.rounded(fontSize, weight: .heavy))
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .buttonStyle(ChunkyButtonStyle(color: Theme.leaf))
        .accessibilityIdentifier("useCropButton")
    }

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)
    }

    // MARK: - Gestures

    private func dragGesture(_ layout: FrameLayout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard layout.side > 0 else { return }
                userAdjusted = true
                let dx = value.translation.width - lastTranslation.width
                let dy = value.translation.height - lastTranslation.height
                lastTranslation = value.translation
                state = framing.panned(state, byX: dx / layout.side, y: dy / layout.side)
            }
            .onEnded { _ in lastTranslation = .zero }
    }

    /// Zooms around the spot where the pinch started, so the rock under the
    /// fingers stays under the fingers.
    private func magnifyGesture(_ layout: FrameLayout) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard layout.side > 0 else { return }
                userAdjusted = true
                let factor = value.magnification / max(lastMagnification, 0.01)
                lastMagnification = value.magnification
                let anchor = layout.frameUnits(value.startLocation)
                state = framing.zoomed(state, to: state.zoom * factor, aroundX: anchor.x, y: anchor.y)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    // MARK: - Actions

    private func nudge(x: Double, y: Double) {
        userAdjusted = true
        state = framing.panned(state, byX: x, y: y)
    }

    private func useFramedPhoto() {
        let rect = framing.cropRect(for: state)
        onUse(photo.cropping(to: rect) ?? photo)
    }

    /// Asks Vision where the rock is and, unless the kid already chose a
    /// framing, glides the frame onto it.
    private func findRock() async {
        let photo = self.photo
        let rect = await Task.detached(priority: .userInitiated) {
            SubjectFinder.suggestedCrop(for: photo)
        }.value
        isSearching = false
        guard let rect else { return }
        let suggested = framing.state(showing: rect)
        // A suggestion that is basically the whole photo isn't worth a button.
        guard suggested.zoom > 1.05 || abs(suggested.offsetX) > 0.02 || abs(suggested.offsetY) > 0.02 else { return }
        suggestion = suggested
        guard !userAdjusted else { return }
        withAnimation(animation) { state = suggested }
    }
}
