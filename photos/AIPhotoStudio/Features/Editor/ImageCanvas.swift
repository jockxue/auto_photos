import CoreGraphics
import SwiftUI

enum CanvasContentMode: String, CaseIterable, Hashable {
    case fit = "Fit"
    case fill = "Fill"
}

/// Ephemeral viewport state. It is intentionally not part of EditState and is
/// never included in export or persisted project data.
struct CanvasTransform: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    mutating func zoom(by factor: CGFloat) {
        scale = min(max(scale * factor, 1), 8)
    }

    mutating func pan(by translation: CGSize) {
        offset.width += translation.width
        offset.height += translation.height
    }

    mutating func reset() {
        scale = 1
        offset = .zero
    }
}

struct CanvasPresentationState: Equatable {
    var transform = CanvasTransform()
    var showsOriginal = false

    mutating func setComparing(_ isPressed: Bool) {
        showsOriginal = isPressed
    }
}

struct ImageViewportMapper: Equatable {
    let canvasSize: CGSize
    let imageSize: CGSize
    let mode: CanvasContentMode
    let transform: CanvasTransform

    var displayRect: CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }
        let fitScale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let fillScale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let scale = (mode == .fit ? fitScale : fillScale) * transform.scale
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2 + transform.offset.width,
            y: (canvasSize.height - size.height) / 2 + transform.offset.height,
            width: size.width,
            height: size.height
        )
    }

    func viewportRect(for sourceRect: NormalizedRect) -> CGRect {
        let source = sourceRect.clamped
        let display = displayRect
        return CGRect(
            x: display.minX + display.width * source.x,
            y: display.minY + display.height * (1 - source.y - source.height),
            width: display.width * source.width,
            height: display.height * source.height
        )
    }

    func sourceRect(moving sourceRect: NormalizedRect, byViewport translation: CGSize) -> NormalizedRect {
        let display = displayRect
        guard display.width > 0, display.height > 0 else { return sourceRect }
        var result = sourceRect
        result.x += translation.width / display.width
        result.y -= translation.height / display.height
        return result.clamped
    }

    func sourceRect(movingImageFor sourceRect: NormalizedRect, byViewport translation: CGSize) -> NormalizedRect {
        self.sourceRect(moving: sourceRect, byViewport: CGSize(
            width: -translation.width,
            height: -translation.height
        ))
    }
}

struct ImageCanvas: View {
    let editedImage: CGImage?
    let originalImage: CGImage?
    private let crop: Binding<CropState>?
    private let onCropEditingChanged: (Bool) -> Void

    @State private var mode: CanvasContentMode = .fit
    @State private var presentation = CanvasPresentationState()
    @State private var gestureScale: CGFloat = 1
    @State private var gestureOffset: CGSize = .zero
    @State private var cropPanIsActive = false

    init(
        editedImage: CGImage?,
        originalImage: CGImage?,
        crop: Binding<CropState>? = nil,
        onCropEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.editedImage = editedImage
        self.originalImage = originalImage
        self.crop = crop
        self.onCropEditingChanged = onCropEditingChanged
    }

    var body: some View {
        GeometryReader { proxy in
            let displayedImage = crop == nil
                ? (presentation.showsOriginal ? originalImage : editedImage)
                : originalImage
            let imageSize = displayedImage.map {
                CGSize(width: CGFloat($0.width), height: CGFloat($0.height))
            } ?? .zero
            let transientTransform = CanvasTransform(
                scale: presentation.transform.scale * gestureScale,
                offset: CGSize(
                    width: presentation.transform.offset.width + gestureOffset.width,
                    height: presentation.transform.offset.height + gestureOffset.height
                )
            )
            let baseMapper = ImageViewportMapper(
                canvasSize: proxy.size,
                imageSize: imageSize,
                mode: mode,
                transform: presentation.transform
            )
            let imageMapper = ImageViewportMapper(
                canvasSize: proxy.size,
                imageSize: imageSize,
                mode: mode,
                transform: transientTransform
            )
            ZStack(alignment: .topTrailing) {
                Color.black
                if let image = displayedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: imageMapper.displayRect.width, height: imageMapper.displayRect.height)
                        .position(x: imageMapper.displayRect.midX, y: imageMapper.displayRect.midY)
                        .accessibilityLabel(L10n.text(presentation.showsOriginal ? "Original photo" : "Edited photo"))
                } else {
                    ProgressView().tint(.white)
                }

                if let crop {
                    CropFrameOverlay(
                        crop: crop,
                        mapper: baseMapper,
                        onEditingChanged: onCropEditingChanged
                    )
                }

                HStack(spacing: 8) {
                    Picker(L10n.text("Content mode"), selection: $mode) {
                        ForEach(CanvasContentMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    Button {
                        presentation.transform.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L10n.text("Reset view"))
                }
                .padding(10)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(mapper: baseMapper))
            .simultaneousGesture(magnificationGesture)
            .onTapGesture(count: 2) {
                guard crop == nil else { return }
                if presentation.transform.scale > 1 {
                    presentation.transform.reset()
                } else {
                    presentation.transform.zoom(by: 2)
                }
            }
            .onLongPressGesture(
                minimumDuration: 0.25,
                maximumDistance: 30,
                pressing: { presentation.setComparing($0) },
                perform: {}
            )
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged {
                guard crop == nil else { return }
                gestureScale = $0
            }
            .onEnded {
                guard crop == nil else { return }
                presentation.transform.zoom(by: $0)
                gestureScale = 1
            }
    }

    private func dragGesture(mapper: ImageViewportMapper) -> some Gesture {
        DragGesture()
            .onChanged {
                gestureOffset = $0.translation
                if crop != nil, !cropPanIsActive {
                    cropPanIsActive = true
                    onCropEditingChanged(true)
                }
            }
            .onEnded {
                if let crop {
                    var value = crop.wrappedValue
                    value.normalizedRect = mapper.sourceRect(
                        movingImageFor: value.normalizedRect,
                        byViewport: $0.translation
                    )
                    crop.wrappedValue = value
                    cropPanIsActive = false
                    onCropEditingChanged(false)
                } else {
                    presentation.transform.pan(by: $0.translation)
                }
                gestureOffset = .zero
            }
    }
}

private struct CropFrameOverlay: View {
    @Binding var crop: CropState
    let mapper: ImageViewportMapper
    let onEditingChanged: (Bool) -> Void
    @State private var startRect: NormalizedRect?

    var body: some View {
        let frame = mapper.viewportRect(for: crop.normalizedRect)
        Rectangle()
            .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
            .background(Color.black.opacity(0.08))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if startRect == nil {
                            startRect = crop.normalizedRect
                            onEditingChanged(true)
                        }
                        guard let initial = startRect else { return }
                        crop.normalizedRect = mapper.sourceRect(
                            moving: initial,
                            byViewport: value.translation
                        )
                    }
                    .onEnded { _ in
                        startRect = nil
                        onEditingChanged(false)
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if startRect == nil {
                            startRect = crop.normalizedRect
                            onEditingChanged(true)
                        }
                        guard let initial = startRect else { return }
                        let width = initial.width / scale
                        let height = initial.height / scale
                        crop.normalizedRect = NormalizedRect(
                            x: initial.x + (initial.width - width) / 2,
                            y: initial.y + (initial.height - height) / 2,
                            width: width,
                            height: height
                        ).clamped
                    }
                    .onEnded { _ in
                        startRect = nil
                        onEditingChanged(false)
                    }
            )
        .accessibilityLabel(L10n.text("Crop frame"))
    }
}
