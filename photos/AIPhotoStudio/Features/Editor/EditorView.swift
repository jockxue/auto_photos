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
    private let onRequestClose: (() -> Void)?
    @State private var selectedTool: Tool = .filter
    @State private var presetGroup: PresetGroup = .recommended
    @State private var isComparing = false
    @State private var presentsManualAdjust = false
    @State private var saveError: String?
    @State private var exportPayload: EditorExportPayload?

    init(
        original: OriginalImage = ImageSourceFactory.makeTestImage(),
        project: PhotoProject? = nil,
        repository: PhotoProjectRepository? = nil,
        onRequestClose: (() -> Void)? = nil
    ) {
        self.onRequestClose = onRequestClose
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
            editorTabBar
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $presentsManualAdjust) {
            ManualAdjustView(session: session, onSave: saveAndClose)
        }
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
                Button(action: closeEditor) {
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
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .disabled(session.exportProject == nil)
                .accessibilityLabel(L10n.text("Export"))
                Button(action: saveAndClose) {
                    Text(L10n.text("Save"))
                        .font(FilmToneTheme.button)
                        .foregroundStyle(FilmToneTheme.accent)
                }
            }
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
                editorTab(.recipe, symbol: "swatchpalette", title: "Save Grade")
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
            if tool == .adjust {
                presentsManualAdjust = true
            } else {
                selectedTool = tool
            }
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
        Task {
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
            EmptyView()
        case .curves:
            VStack(spacing: 8) {
                HStack {
                    Button {
                        selectedTool = .filter
                    } label: {
                        Label(L10n.text("Adjust"), systemImage: "chevron.left")
                            .font(FilmToneTheme.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                curveControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(FilmToneTheme.chipBackground, in: Capsule())
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
            .buttonStyle(.plain)
            .foregroundStyle(FilmToneTheme.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

private struct ManualAdjustView: View {
    @ObservedObject var session: EditorSession
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isComparing = false

    private let controls: [(AdjustmentKey, String)] = [
        (.exposure, "Exposure"),
        (.vibrance, "Brilliance"),
        (.highlights, "Highlights"),
        (.shadows, "Shadows")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
            VStack(spacing: 22) {
                ForEach(controls, id: \.0) { key, title in
                    let descriptor = key.descriptor
                    AppSlider(
                        title: L10n.text(title),
                        value: Binding(
                            get: { session.value(for: key) },
                            set: { session.setValue($0, for: key) }
                        ),
                        range: descriptor.range,
                        displayValue: descriptor.displayValue,
                        onEditingChanged: {
                            $0 ? session.beginAdjustment(key) : session.endAdjustment()
                        },
                        titleResets: false,
                        valueIsAccent: true
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            footer
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            Text(L10n.text("Manual Adjust"))
                .font(FilmToneTheme.pageTitle)
                .lineLimit(1)
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel(L10n.text("Back"))
                Spacer()
                Button(action: onSave) {
                    Text(L10n.text("Save"))
                        .font(FilmToneTheme.button)
                        .foregroundStyle(FilmToneTheme.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            ImageCanvas(
                editedImage: editedImage,
                originalImage: session.originalPreview,
                isComparing: $isComparing,
                showsChrome: false
            )
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button(action: resetShownControls) {
                Text(L10n.text("Reset"))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FilmToneTheme.secondaryText)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: { dismiss() }) {
                Text(L10n.text("Done"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FilmToneTheme.accentText)
                    .frame(width: 99, height: 44)
                    .background(
                        FilmToneTheme.accent,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(FilmToneTheme.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FilmToneTheme.divider)
                .frame(height: 1)
        }
    }

    private var editedImage: CGImage? {
        if case .ready(let image) = session.preview { return image }
        return nil
    }

    private func resetShownControls() {
        controls.forEach { session.resetCurrent($0.0) }
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
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task { image = await session.filterThumbnail(for: definition) }
    }
}
