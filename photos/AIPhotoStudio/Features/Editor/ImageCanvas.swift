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

struct ImageCanvas: View {
    let editedImage: CGImage?
    let originalImage: CGImage?

    @State private var mode: CanvasContentMode = .fit
    @State private var presentation = CanvasPresentationState()
    @State private var gestureScale: CGFloat = 1
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black
                if let image = presentation.showsOriginal ? originalImage : editedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: mode == .fit ? .fit : .fill)
                        .scaleEffect(presentation.transform.scale * gestureScale)
                        .offset(
                            x: presentation.transform.offset.width + gestureOffset.width,
                            y: presentation.transform.offset.height + gestureOffset.height
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityLabel(presentation.showsOriginal ? "Original photo" : "Edited photo")
                } else {
                    ProgressView().tint(.white)
                }

                HStack(spacing: 8) {
                    Picker("Content mode", selection: $mode) {
                        ForEach(CanvasContentMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    Button {
                        presentation.transform.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset view")
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
            .onTapGesture(count: 2) {
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
            .onChanged { gestureScale = $0 }
            .onEnded {
                presentation.transform.zoom(by: $0)
                gestureScale = 1
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gestureOffset = $0.translation }
            .onEnded {
                presentation.transform.pan(by: $0.translation)
                gestureOffset = .zero
            }
    }
}

struct CropOverlay: View {
    @Binding var crop: CropState
    let onEditingChanged: (Bool) -> Void
    @State private var startRect: NormalizedRect?

    var body: some View {
        GeometryReader { proxy in
            let rect = crop.normalizedRect.clamped
            Rectangle()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                .background(Color.black.opacity(0.08))
                .frame(
                    width: proxy.size.width * rect.width,
                    height: proxy.size.height * rect.height
                )
                .position(
                    x: proxy.size.width * (rect.x + rect.width / 2),
                    y: proxy.size.height * (rect.y + rect.height / 2)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if startRect == nil {
                                startRect = crop.normalizedRect
                                onEditingChanged(true)
                            }
                            guard var updated = startRect else { return }
                            updated.x += value.translation.width / proxy.size.width
                            updated.y += value.translation.height / proxy.size.height
                            crop.normalizedRect = updated.clamped
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
        }
        .accessibilityLabel("Crop frame")
    }
}
