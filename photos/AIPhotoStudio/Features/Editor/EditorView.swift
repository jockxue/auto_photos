import SwiftUI

struct EditorView: View {
    enum Tool: String, CaseIterable, Hashable {
        case adjust = "Adjust"
        case filter = "Filter"
        case crop = "Crop"
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
                        Label(tool.rawValue, systemImage: tool.icon)
                    }
                    .tint(selectedTool == tool ? .indigo : .secondary)
                }
            }

            toolControls
        }
        .navigationBarBackButtonHidden()
        .alert("Unable to save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
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
                .accessibilityLabel("Back")
            Text(session.title).font(.headline).lineLimit(1)
            Spacer()
            Button(action: session.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo)
                .accessibilityLabel("Undo")
            Button(action: session.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo)
                .accessibilityLabel("Redo")
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
                .accessibilityLabel("Export")
            Button("Done") {
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
                            Text(category.rawValue).font(.headline)
                            ForEach(AdjustmentKey.allCases.filter { $0.descriptor.category == category }) { key in
                                let descriptor = key.descriptor
                                AppSlider(
                                    title: descriptor.title,
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
        case .filter:
            filterControls
        case .crop:
            cropControls
        }
    }

    private var filterControls: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(FilterDefinition.all) { definition in
                        Button(definition.title) {
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
                    title: "Intensity",
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
                        Button(ratio.title) {
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
                title: "Rotate",
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
                onEditingChanged: { $0 ? session.beginCropEdit(summary: "Rotate") : session.endCropEdit() }
            )
            HStack {
                Button("↶ 90°") { var value = session.cropState; value.rotateLeft(); session.updateCrop(value, summary: "Rotate Left") }
                Button("90° ↷") { var value = session.cropState; value.rotateRight(); session.updateCrop(value, summary: "Rotate Right") }
                Button("Flip H") { var value = session.cropState; value.isFlippedHorizontally.toggle(); session.updateCrop(value, summary: "Flip Horizontal") }
                Button("Flip V") { var value = session.cropState; value.isFlippedVertically.toggle(); session.updateCrop(value, summary: "Flip Vertical") }
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
        case .filter: "camera.filters"
        case .crop: "crop"
        }
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
