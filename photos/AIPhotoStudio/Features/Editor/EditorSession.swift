import Combine
import CoreGraphics
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

    private let renderer: any RenderEngineProtocol
    private let repository: PhotoProjectRepository?
    private var project: PhotoProject?
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var renderTask: Task<Void, Never>?

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
        renderPreview()
        renderOriginal()
    }

    var editState: EditState { document.editState }
    var title: String { project?.title ?? "Editor" }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func value(for key: AdjustmentKey) -> Double {
        document.editState.adjustments[key]
    }

    func setValue(_ value: Double, for key: AdjustmentKey) {
        guard value != document.editState.adjustments[key] else { return }
        undoStack.append(document.editState)
        redoStack.removeAll()
        document.editState.adjustments[key] = value
        renderPreview()
    }

    func reset() {
        undoStack.append(document.editState)
        redoStack.removeAll()
        document.editState = EditState()
        renderPreview()
    }

    func undo() {
        guard let state = undoStack.popLast() else { return }
        redoStack.append(document.editState)
        document.editState = state
        renderPreview()
    }

    func redo() {
        guard let state = redoStack.popLast() else { return }
        undoStack.append(document.editState)
        document.editState = state
        renderPreview()
    }

    /// Persists only the project/edit recipe. The immutable original file is not rewritten.
    func complete() async throws {
        guard var project, let repository else { return }
        project.editState = document.editState
        try await repository.update(project)
        self.project = project
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

    private func renderPreview() {
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

    private func renderOriginal() {
        let renderer = renderer
        let request = RenderRequest(original: document.original, edits: .init(), maximumDimension: 2048)
        Task {
            originalPreview = try? await Task.detached(priority: .userInitiated) {
                try renderer.render(request).cgImage
            }.value
        }
    }
}
