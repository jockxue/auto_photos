import SwiftUI

struct EditorView: View {
    enum Tool: String, CaseIterable, Hashable {
        case adjust = "Adjust"
        case filter = "Filter"
        case crop = "Crop"
        case recipe = "Recipe"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: EditorSession
    private let onRequestClose: (() -> Void)?
    @State private var selectedTool: Tool
    @State private var activeAdjustTool: AdjustTool?
    @State private var presetGroup: PresetGroup = .recommended
    @State private var isComparing = false
    @State private var isClosing = false
    @State private var saveError: String?
    @State private var exportPayload: EditorExportPayload?

    init(
        original: OriginalImage,
        project: PhotoProject? = nil,
        repository: PhotoProjectRepository? = nil,
        onRequestClose: (() -> Void)? = nil,
        initialTool: Tool = .filter
    ) {
        self.onRequestClose = onRequestClose
        _selectedTool = State(initialValue: initialTool)
        _session = StateObject(wrappedValue: EditorSession(
            original: original,
            project: project,
            repository: repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            preview
            toolControls
            if activeAdjustTool == nil {
                editorTabBar
            }
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
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
        .navigationDestination(isPresented: Binding(
            get: { exportPayload != nil },
            set: { if !$0 { exportPayload = nil } }
        )) {
            if let exportPayload {
                ExportView(
                    project: exportPayload.project,
                    editState: exportPayload.editState,
                    repository: exportPayload.repository,
                    preview: editedImage,
                    onReturnHome: closeEditor
                )
            }
        }
    }

    private var editedImage: CGImage? {
        switch session.preview {
        case .ready(let image): image
        default: nil
        }
    }

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
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
                },
                isComparing: $isComparing,
                showsChrome: false
            )
            if selectedTool != .crop {
                Image(systemName: isComparing ? "eye.fill" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FilmToneTheme.primaryText)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isComparing = true }
                            .onEnded { _ in isComparing = false }
                    )
                    .accessibilityLabel(L10n.text("Compare"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorHeader: some View {
        ZStack {
            Text(L10n.text("Edit Photo"))
                .font(FilmToneTheme.pageTitle)
                .lineLimit(1)
            HStack(spacing: 16) {
                Button(action: saveAndClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel(L10n.text("Back"))
                Spacer()
                Button(action: session.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .disabled(!session.canUndo)
                .accessibilityLabel(L10n.text("Undo"))
                Button(action: session.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .disabled(!session.canRedo)
                .accessibilityLabel(L10n.text("Redo"))
                Button(action: export) {
                    Text(L10n.text("Export"))
                        .font(FilmToneTheme.button)
                        .foregroundStyle(FilmToneTheme.accent)
                }
                .disabled(session.exportProject == nil)
            }
            .disabled(activeAdjustTool != nil || isClosing)
            .opacity(activeAdjustTool == nil ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var editorTabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FilmToneTheme.divider)
                .frame(height: 1)
            HStack(spacing: 0) {
                editorTab(.filter, symbol: "camera.filters", title: "Presets")
                editorTab(.adjust, symbol: "slider.horizontal.3", title: "Adjust")
                editorTab(.crop, symbol: "crop", title: "Crop")
                editorTab(.recipe, symbol: "swatchpalette", title: "Recipe")
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(FilmToneTheme.tabBar.ignoresSafeArea(edges: .bottom))
    }

    private func editorTab(_ tool: Tool, symbol: String, title: String) -> some View {
        let selected = selectedTool == tool
        let color = selected ? FilmToneTheme.accent : FilmToneTheme.secondaryText
        return Button {
            selectedTool = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 20)
                Text(L10n.text(title))
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func export() {
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
    }

    private func closeEditor() {
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    private func saveAndClose() {
        guard !isClosing else { return }
        isClosing = true
        Task {
            defer { isClosing = false }
            do {
                try await session.complete()
                closeEditor()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var toolControls: some View {
        switch selectedTool {
        case .adjust:
            if let activeAdjustTool {
                AdjustToolPanel(tool: activeAdjustTool, session: session) {
                    self.activeAdjustTool = nil
                }
            } else {
                AdjustToolStrip(session: session) { tool in
                    session.beginToolEdit(summary: L10n.text(tool.title))
                    activeAdjustTool = tool
                }
            }
        case .filter:
            filterControls
        case .crop:
            cropControls
        case .recipe:
            RecipeView(session: session)
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Presets"))
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PresetGroup.allCases) { group in
                        let selected = presetGroup == group
                        Button {
                            presetGroup = group
                        } label: {
                            Text(L10n.text(group.titleKey))
                                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? FilmToneTheme.accentText : FilmToneTheme.primaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(
                                    selected ? FilmToneTheme.accent : FilmToneTheme.chipBackground,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(presetGroup.filters) { definition in
                        let selected = (session.filterConfig?.identifier ?? "original") == definition.id
                        Button {
                            session.updateFilter(definition.id == "original" ? nil : FilterConfig(identifier: definition.id))
                        } label: {
                            VStack(spacing: 6) {
                                FilterThumbnail(definition: definition, session: session)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? FilmToneTheme.accent : Color.clear, lineWidth: 2)
                                    }
                                Text(L10n.text(definition.title))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(selected ? FilmToneTheme.accent : FilmToneTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            if let config = session.filterConfig {
                AppSlider(
                    title: L10n.text("Preset Strength"),
                    value: Binding(
                        get: { session.filterConfig?.intensity ?? 0 },
                        set: { session.setFilterPreview(FilterConfig(identifier: config.identifier, intensity: $0)) }
                    ),
                    range: 0...100,
                    displayValue: { String(format: "%.0f", $0) },
                    onEditingChanged: { $0 ? session.beginFilterEdit() : session.endFilterEdit() }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    private var cropControls: some View {
        let crop = session.cropState
        return VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                        ToolChip(title: ratio.title, selected: crop.aspectRatio == ratio) {
                            var value = session.cropState
                            value.aspectRatio = ratio
                            value.normalizedRect = CropLayout.rect(
                                for: ratio,
                                sourceAspectRatio: session.sourceAspectRatio
                            )
                            session.updateCrop(value)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            VStack(spacing: 12) {
                HStack {
                    Text("-45°")
                    Spacer()
                    Text(L10n.text("Rotate"))
                    Text(String(format: "%+.0f°", crop.fineRotationDegrees))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.accent)
                    Spacer()
                    Text("+45°")
                }
                .font(.system(size: 13))
                .foregroundStyle(FilmToneTheme.secondaryText)
                .monospacedDigit()
                ToolSlider(
                    value: Binding(
                        get: { session.cropState.fineRotationDegrees },
                        set: {
                            var value = session.cropState
                            value.fineRotationDegrees = $0
                            session.setCropPreview(value)
                        }
                    ),
                    range: -45...45,
                    defaultValue: 0,
                    onEditingChanged: {
                        $0 ? session.beginCropEdit(summary: L10n.text("Rotate")) : session.endCropEdit()
                    }
                )
                .accessibilityLabel(L10n.text("Rotate"))
                .accessibilityValue(String(format: "%+.0f°", crop.fineRotationDegrees))
            }
            .padding(.horizontal, 16)
            HStack(spacing: 0) {
                cropAction("rotate.left", title: "Rotate Left", active: false) {
                    var value = session.cropState
                    value.rotateLeft()
                    session.updateCrop(value, summary: L10n.text("Rotate Left"))
                }
                cropAction("rotate.right", title: "Rotate Right", active: false) {
                    var value = session.cropState
                    value.rotateRight()
                    session.updateCrop(value, summary: L10n.text("Rotate Right"))
                }
                cropAction(
                    "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    title: "Flip H",
                    active: crop.isFlippedHorizontally
                ) {
                    var value = session.cropState
                    value.isFlippedHorizontally.toggle()
                    session.updateCrop(value, summary: L10n.text("Flip Horizontal"))
                }
                cropAction(
                    "arrow.up.and.down.righttriangle.up.righttriangle.down",
                    title: "Flip V",
                    active: crop.isFlippedVertically
                ) {
                    var value = session.cropState
                    value.isFlippedVertically.toggle()
                    session.updateCrop(value, summary: L10n.text("Flip Vertical"))
                }
                cropAction("arrow.counterclockwise", title: "Reset", active: false) {
                    session.updateCrop(CropState(), summary: L10n.text("Reset"))
                }
                .disabled(crop == CropState())
                .opacity(crop == CropState() ? 0.4 : 1)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 14)
    }

    private func cropAction(
        _ symbol: String,
        title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        CircleToolButton(symbol: symbol, title: title, highlighted: active, action: action)
            .frame(maxWidth: .infinity)
    }
}

private enum PresetGroup: String, CaseIterable, Identifiable {
    case recommended
    case popular
    case film
    case natural
    case portrait
    case mono

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .recommended: "Recommended"
        case .popular: "Popular"
        case .film: "Film"
        case .natural: "Natural"
        case .portrait: "Portrait"
        case .mono: "Black & White"
        }
    }

    var filters: [FilterDefinition] {
        FilterDefinition.all.filter { definition in
            if definition.id == "original" { return true }
            switch self {
            case .recommended:
                return true
            case .popular:
                return ["vivid", "dramatic", "film", "portrait", "vintage"].contains(definition.id)
            case .film:
                return ["film", "vintage", "fade", "instant", "chrome"].contains(definition.id)
            case .natural:
                return ["natural", "warm", "cool"].contains(definition.id)
            case .portrait:
                return definition.id == "portrait"
            case .mono:
                return ["blackWhite", "noir"].contains(definition.id)
            }
        }
    }
}

private struct EditorExportPayload: Identifiable {
    let id = UUID()
    let project: PhotoProject
    let editState: EditState
    let repository: PhotoProjectRepository
}

private struct FilterThumbnail: View {
    let definition: FilterDefinition
    @ObservedObject var session: EditorSession
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: session.originalPreview != nil) {
            image = await session.filterThumbnail(for: definition)
        }
    }
}
