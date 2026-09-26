import SwiftUI

struct EditorView: View {
    enum Tool: String, CaseIterable, Hashable {
        case adjust = "Adjust"
        case curves = "Curves"
        case filter = "Filter"
        case crop = "Crop"
        case recipe = "Recipe"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: EditorSession
    @State private var selectedTool: Tool = .adjust
    @State private var saveError: String?
    @State private var exportPayload: EditorExportPayload?

    init(
        original: OriginalImage = ImageSourceFactory.makeTestImage(),
        project: PhotoProject? = nil,
        repository: PhotoProjectRepository? = nil
    ) {
        _session = StateObject(wrappedValue: EditorSession(
            original: original,
            project: project,
            repository: repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            ImageCanvas(
                editedImage: editedImage,
                originalImage: selectedTool == .crop
                    ? (session.cropSourcePreview ?? session.originalPreview)
                    : session.originalPreview,
                crop: selectedTool == .crop ? Binding(
                    get: { session.cropState },
                    set: { session.setCropPreview($0) }
                ) : nil,
                onCropEditingChanged: {
                    $0 ? session.beginCropEdit() : session.endCropEdit()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppToolbar {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Label(L10n.text(tool.rawValue), systemImage: tool.icon)
                    }
                    .tint(selectedTool == tool ? .indigo : .secondary)
                }
            }

            toolControls
        }
        .navigationBarBackButtonHidden()
        .alert(L10n.text("Unable to save"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(L10n.text("OK"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task {
                do {
                    try await session.flushPendingSave()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        }
        .onChange(of: session.persistenceError) { error in
            if let error { saveError = error }
        }
        .sheet(item: $exportPayload) { payload in
            ExportView(
                project: payload.project,
                editState: payload.editState,
                repository: payload.repository
            )
        }
    }

    private var editedImage: CGImage? {
        switch session.preview {
        case .ready(let image): image
        default: nil
        }
    }

    private var editorHeader: some View {
        HStack {
            Button(action: { dismiss() }) { Image(systemName: "chevron.left") }
                .accessibilityLabel(L10n.text("Back"))
            Text(session.title).font(.headline).lineLimit(1)
            Spacer()
            Button(action: session.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo)
                .accessibilityLabel(L10n.text("Undo"))
            Button(action: session.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo)
                .accessibilityLabel(L10n.text("Redo"))
            Button(action: {
                Task {
                    do {
                        let (project, state, repository) = try await session.prepareExport()
                        exportPayload = EditorExportPayload(
                            project: project,
                            editState: state,
                            repository: repository
                        )
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }) { Image(systemName: "square.and.arrow.up") }
                .disabled(session.exportProject == nil)
                .accessibilityLabel(L10n.text("Export"))
            Button(L10n.text("Done")) {
                Task {
                    do {
                        try await session.complete()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var toolControls: some View {
        switch selectedTool {
        case .adjust:
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(AdjustmentCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text(category.rawValue)).font(.headline)
                            ForEach(AdjustmentKey.allCases.filter { $0.descriptor.category == category }) { key in
                                let descriptor = key.descriptor
                                AppSlider(
                                    title: L10n.text(descriptor.title),
                                    value: Binding(
                                        get: { session.value(for: key) },
                                        set: { session.setValue($0, for: key) }
                                    ),
                                    range: descriptor.range,
                                    displayValue: descriptor.displayValue,
                                    onEditingChanged: {
                                        $0 ? session.beginAdjustment(key) : session.endAdjustment()
                                    },
                                    onReset: { session.resetCurrent(key) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .padding()
        case .curves:
            curveControls
        case .filter:
            filterControls
        case .crop:
            cropControls
        case .recipe:
            RecipeView(session: session)
        }
    }

    private var curveControls: some View {
        CurveControls(session: session)
    }

    private var filterControls: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(FilterDefinition.all) { definition in
                        Button(L10n.text(definition.title)) {
                            session.updateFilter(definition.id == "original" ? nil : FilterConfig(identifier: definition.id))
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.titleAndIcon)
                        .overlay(alignment: .top) {
                            FilterThumbnail(definition: definition, session: session)
                                .offset(y: -54)
                        }
                        .padding(.top, 58)
                    }
                }
            }
            if let config = session.filterConfig {
                AppSlider(
                    title: L10n.text("Intensity"),
                    value: Binding(
                        get: { session.filterConfig?.intensity ?? 0 },
                        set: { session.setFilterPreview(FilterConfig(identifier: config.identifier, intensity: $0)) }
                    ),
                    range: 0...100,
                    onEditingChanged: { $0 ? session.beginFilterEdit() : session.endFilterEdit() }
                )
            }
        }
        .padding()
    }

    private var cropControls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                        Button(L10n.text(ratio.title)) {
                            var crop = session.cropState
                            crop.aspectRatio = ratio
                            crop.normalizedRect = CropLayout.rect(
                                for: ratio,
                                sourceAspectRatio: session.sourceAspectRatio
                            )
                            session.updateCrop(crop)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            AppSlider(
                title: L10n.text("Rotate"),
                value: Binding(
                    get: { session.cropState.fineRotationDegrees },
                    set: {
                        var crop = session.cropState
                        crop.fineRotationDegrees = $0
                        session.setCropPreview(crop)
                    }
                ),
                range: -45...45,
                displayValue: { String(format: "%+.0f°", $0) },
                onEditingChanged: { $0 ? session.beginCropEdit(summary: L10n.text("Rotate")) : session.endCropEdit() }
            )
            HStack {
                Button(L10n.text("Rotate Left")) { var value = session.cropState; value.rotateLeft(); session.updateCrop(value, summary: L10n.text("Rotate Left")) }
                Button(L10n.text("Rotate Right")) { var value = session.cropState; value.rotateRight(); session.updateCrop(value, summary: L10n.text("Rotate Right")) }
                Button(L10n.text("Flip H")) { var value = session.cropState; value.isFlippedHorizontally.toggle(); session.updateCrop(value, summary: L10n.text("Flip Horizontal")) }
                Button(L10n.text("Flip V")) { var value = session.cropState; value.isFlippedVertically.toggle(); session.updateCrop(value, summary: L10n.text("Flip Vertical")) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

private struct EditorExportPayload: Identifiable {
    let id = UUID()
    let project: PhotoProject
    let editState: EditState
    let repository: PhotoProjectRepository
}

private extension EditorView.Tool {
    var icon: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .curves: "point.topleft.down.curvedto.point.bottomright.up"
        case .filter: "camera.filters"
        case .crop: "crop"
        case .recipe: "swatch.variable"
        }
    }
}

private struct CurveControls: View {
    @ObservedObject var session: EditorSession
    @State private var channel: CurveChannel = .rgb

    var body: some View {
        VStack(spacing: 12) {
            Picker(L10n.text("Channel"), selection: $channel) {
                ForEach(CurveChannel.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            CurveGraph(
                curve: Binding(
                    get: { session.curves[channel] },
                    set: { updated in
                        var curves = session.curves
                        curves[channel] = updated
                        session.setCurvePreview(curves)
                    }
                ),
                tint: tint,
                onEditingChanged: { editing in
                    editing ? session.beginCurveEdit() : session.endCurveEdit()
                }
            )
            Button(L10n.text("Reset Curve")) { session.resetCurves() }
                .buttonStyle(.bordered)
                .disabled(session.curves.isIdentity)
        }
        .padding()
    }

    private var tint: Color {
        switch channel {
        case .rgb: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }
}

private struct CurveGraph: View {
    @Binding var curve: ChannelCurve
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.35))
                Path { path in
                    stride(from: 0.25, through: 0.75, by: 0.25).forEach { mark in
                        let x = size.width * mark
                        let y = size.height * (1 - mark)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                Path { path in
                    guard let first = curve.points.first else { return }
                    path.move(to: position(first, in: size))
                    curve.points.dropFirst().forEach { path.addLine(to: position($0, in: size)) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(curve.points.indices, id: \.self) { index in
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .position(position(curve.points[index], in: size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    onEditingChanged(true)
                                    let y = 1 - min(max(value.location.y / max(size.height, 1), 0), 1)
                                    curve.setPoint(at: index, y: y)
                                }
                                .onEnded { _ in onEditingChanged(false) }
                        )
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel(L10n.text("Curves"))
    }

    private func position(_ point: CurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * point.x, y: size.height * (1 - point.y))
    }
}

private struct FilterThumbnail: View {
    let definition: FilterDefinition
    let session: EditorSession
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task { image = await session.filterThumbnail(for: definition) }
    }
}
