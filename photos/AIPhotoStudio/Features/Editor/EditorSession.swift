import Combine
import CoreGraphics
import CoreImage
import Foundation

@MainActor
final class EditorSession: ObservableObject {
    enum PreviewState {
        case loading
        case ready(CGImage)
        case failed(String)
    }

    @Published private(set) var document: PhotoDocument
    @Published private(set) var preview: PreviewState = .loading
    @Published private(set) var originalPreview: CGImage?
    @Published private(set) var cropSourcePreview: CGImage?
    @Published private(set) var persistenceError: String?

    private let renderer: any RenderEngineProtocol
    private let repository: PhotoProjectRepository?
    private var project: PhotoProject?
    private var history = EditHistory()
    private let filterThumbnailCache = FilterThumbnailCache()
    private var renderTask: Task<Void, Never>?
    private var cropRenderTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    init(
        original: OriginalImage,
        project: PhotoProject? = nil,
        repository: PhotoProjectRepository? = nil,
        renderer: any RenderEngineProtocol = CoreImageRenderEngine()
    ) {
        document = PhotoDocument(original: original, editState: project?.editState ?? .init())
        self.project = project
        self.repository = repository
        self.renderer = renderer
        renderPreview(debounced: false)
        renderOriginal()
        renderCropSource()
    }

    var editState: EditState { document.editState }
    var cropState: CropState { document.editState.geometry }
    var filterConfig: FilterConfig? { document.editState.filter }
    var sourceAspectRatio: Double {
        let size = GeometryOutputPlanner.outputSize(
            originalWidth: Int(document.original.metadata.pixelSize.width),
            originalHeight: Int(document.original.metadata.pixelSize.height),
            orientation: document.original.metadata.orientation,
            crop: .init(),
            rotationDegrees: cropState.rotationDegrees
        )
        return size.height == 0 ? 1 : Double(size.width / size.height)
    }
    var exportProject: PhotoProject? { project }
    var projectRepository: PhotoProjectRepository? { repository }

    func filterThumbnail(for definition: FilterDefinition) async -> CGImage? {
        guard let originalPreview else { return nil }
        let key = FilterThumbnailCache.Key(
            projectID: project?.id ?? document.id,
            version: project?.currentVersion ?? 1,
            filterID: definition.id
        )
        if let cached = await filterThumbnailCache.value(for: key) { return cached }
        var image = CIImage(cgImage: originalPreview)
        let ratio = min(1, 120 / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        image = CoreImageFilterEngine().apply(
            FilterConfig(identifier: definition.id, intensity: 100),
            to: image
        )
        guard let output = CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(image, from: image.extent.integral) else { return nil }
        await filterThumbnailCache.insert(output, for: key)
        return output
    }
    var title: String { project?.title ?? "Editor" }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func value(for key: AdjustmentKey) -> Double {
        document.editState.adjustments[key]
    }

    func setValue(_ value: Double, for key: AdjustmentKey) {
        guard value != document.editState.adjustments[key] else { return }
        let before = document.editState
        document.editState.adjustments[key] = value
        if !history.isCoalescing {
            history.record(kind: .adjust, before: before, after: document.editState, summary: key.title)
        }
        renderPreview()
    }

    func beginAdjustment(_ key: AdjustmentKey) {
        history.begin(kind: .adjust, state: document.editState, summary: key.title)
    }

    func endAdjustment() {
        history.end(state: document.editState)
        scheduleAutosave()
    }

    func resetCurrent(_ key: AdjustmentKey) {
        let before = document.editState
        document.editState.adjustments[key] = key.descriptor.defaultValue
        history.record(kind: .adjust, before: before, after: document.editState, summary: "Reset \(key.title)")
        renderPreview()
        scheduleAutosave()
    }

    func reset() {
        let before = document.editState
        document.editState = EditState()
        history.record(kind: .adjust, before: before, after: document.editState, summary: "Reset All")
        renderPreview()
        scheduleAutosave()
    }

    func undo() {
        guard let state = history.undo(current: document.editState) else { return }
        document.editState = state
        renderPreview()
        scheduleAutosave()
    }

    func redo() {
        guard let state = history.redo(current: document.editState) else { return }
        document.editState = state
        renderPreview()
        scheduleAutosave()
    }

    func updateFilter(_ config: FilterConfig?) {
        let before = document.editState
        document.editState.filter = config
        history.record(kind: .filter, before: before, after: document.editState, summary: "Filter \(config?.identifier ?? "Original")")
        renderPreview()
        scheduleAutosave()
    }

    func beginFilterEdit() {
        history.begin(kind: .filter, state: document.editState, summary: "Filter")
    }

    func setFilterPreview(_ config: FilterConfig?) {
        document.editState.filter = config
        renderPreview()
    }

    func endFilterEdit() {
        history.end(state: document.editState)
        scheduleAutosave()
    }

    func updateCrop(_ crop: CropState, summary: String = "Crop") {
        let before = document.editState
        document.editState.geometry = crop
        history.record(kind: .crop, before: before, after: document.editState, summary: summary)
        renderPreview()
        renderCropSource()
        scheduleAutosave()
    }

    func beginCropEdit(summary: String = "Crop") {
        history.begin(kind: .crop, state: document.editState, summary: summary)
    }

    func setCropPreview(_ crop: CropState) {
        document.editState.geometry = crop
        renderPreview()
        renderCropSource()
    }

    func endCropEdit() {
        history.end(state: document.editState)
        scheduleAutosave()
    }

    /// Persists only the project/edit recipe. The immutable original file is not rewritten.
    func complete() async throws {
        autosaveTask?.cancel()
        await autosaveTask?.value
        try await persist()
    }

    private func persist() async throws {
        guard let project, let repository else { return }
        let summary = history.latestSummary ?? "Edit"
        do {
            self.project = try await repository.saveEditState(
                projectID: project.id,
                editState: document.editState,
                commandSummary: summary
            )
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            throw error
        }
        if let savedProject = self.project {
            let renderer = renderer
            let request = RenderRequest(
                original: document.original,
                edits: document.editState,
                maximumDimension: 512
            )
            let thumbnail = try await Task.detached(priority: .utility) {
                try renderer.render(request).cgImage
            }.value
            try await repository.replaceThumbnail(thumbnail, for: savedProject)
        }
    }

    func renderExport() async throws -> RenderedImage {
        let exportOriginal: OriginalImage
        if let project, let repository {
            let data = try await repository.originalData(for: project)
            guard let decoded = ImageSourceFactory.decode(data: data) else {
                throw ProjectRepositoryError.unreadableImage
            }
            exportOriginal = decoded
        } else {
            exportOriginal = document.original
        }
        return try renderer.render(RenderRequest(
            original: exportOriginal,
            edits: document.editState,
            maximumDimension: nil
        ))
    }

    func flushPendingSave() async throws {
        try await complete()
    }

    func prepareExport() async throws -> (PhotoProject, EditState, PhotoProjectRepository) {
        try await flushPendingSave()
        guard let project, let repository else {
            throw ProjectRepositoryError.projectNotFound
        }
        return (project, document.editState, repository)
    }

    private func renderPreview(debounced: Bool = true) {
        renderTask?.cancel()
        preview = .loading
        let renderer = renderer
        let request = RenderRequest(
            original: document.original,
            edits: document.editState,
            maximumDimension: 2048
        )
        renderTask = Task {
            do {
                if debounced {
                    try await Task.sleep(nanoseconds: 60_000_000)
                }
                let rendered = try await Task.detached(priority: .userInitiated) {
                    try renderer.render(request)
                }.value
                guard !Task.isCancelled else { return }
                preview = .ready(rendered.cgImage)
            } catch {
                guard !Task.isCancelled else { return }
                preview = .failed(error.localizedDescription)
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                try Task.checkCancellation()
                try await persist()
            } catch is CancellationError {
                return
            } catch {
                persistenceError = error.localizedDescription
            }
        }
    }

    private func renderOriginal() {
        let renderer = renderer
        let request = RenderRequest(original: document.original, edits: .init(), maximumDimension: 2048)
        Task {
            originalPreview = try? await Task.detached(priority: .userInitiated) {
                try renderer.render(request).cgImage
            }.value
        }
    }

    private func renderCropSource() {
        cropRenderTask?.cancel()
        let renderer = renderer
        var edits = document.editState
        edits.geometry.normalizedRect = .init()
        let request = RenderRequest(
            original: document.original,
            edits: edits,
            maximumDimension: 2048
        )
        cropRenderTask = Task {
            do {
                try await Task.sleep(nanoseconds: 40_000_000)
                let image = try await Task.detached(priority: .userInitiated) {
                    try renderer.render(request).cgImage
                }.value
                guard !Task.isCancelled else { return }
                cropSourcePreview = image
            } catch {
                return
            }
        }
    }
}
