import SwiftUI
import UIKit

struct ColorReplicaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ReplicaPhotoSelection()
    @State private var targetThumbnail: UIImage?
    @State private var referenceThumbnail: UIImage?
    @State private var picking: ReplicaPhotoSlot?
    @State private var preview: ReplicaPreviewPayload?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            replicaHeader("Reference Color Match", back: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L10n.text("Bring a favorite color palette to your photo."))
                        .font(FilmToneTheme.body)
                        .foregroundStyle(FilmToneTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Your Photo")).font(FilmToneTheme.sectionTitle)
                        Button { picking = .target } label: {
                            Color.clear
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay {
                                    if let targetThumbnail {
                                        GeometryReader { geometry in
                                            Image(uiImage: targetThumbnail)
                                                .resizable().scaledToFill()
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                .clipped()
                                        }
                                    } else {
                                        VStack(spacing: 12) {
                                            Image(systemName: "plus").font(.system(size: 26, weight: .light))
                                            Text(L10n.text("Add Your Photo")).font(FilmToneTheme.body)
                                        }
                                        .foregroundStyle(FilmToneTheme.secondaryText)
                                    }
                                }
                                .background(FilmToneTheme.cardBackground)
                                .overlay(alignment: .bottomTrailing) {
                                    if targetThumbnail != nil {
                                        Text(L10n.text("Change"))
                                            .font(FilmToneTheme.caption)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(.black.opacity(0.55), in: Capsule())
                                            .padding(12)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Reference Colors")).font(FilmToneTheme.sectionTitle)
                        referenceCard(image: referenceThumbnail, selected: selection.reference != nil) { picking = .reference }
                    }
                }
                .padding(20)
            }
            VStack(spacing: 14) {
                Text(L10n.text(isAnalyzing ? "Preparing your color preview…" : selection.hintKey))
                    .font(FilmToneTheme.caption).foregroundStyle(FilmToneTheme.secondaryText)
                Button { Task { await generatePreview() } } label: {
                    HStack(spacing: 10) {
                        if isAnalyzing { ProgressView().tint(FilmToneTheme.primaryText) }
                        Text(L10n.text(isAnalyzing ? "Analyzing reference…" : "Generate Color Preview"))
                        if selection.isComplete && !isAnalyzing {
                            Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                .buttonStyle(ReplicaPrimaryButtonStyle())
                .disabled(!selection.isComplete || isAnalyzing)
            }
            .padding(20)
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .disabled(isAnalyzing)
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $picking) { slot in
            SystemPhotoPicker(
                selectionLimit: 1,
                onSelection: { photos in
                    picking = nil
                    guard let photo = photos.first else { return }
                    selection.select(photo, for: slot)
                    let thumbnail = replicaThumbnail(photo)
                    if slot == .target {
                        targetThumbnail = thumbnail
                    } else {
                        referenceThumbnail = thumbnail
                    }
                },
                onCancel: { picking = nil },
                onFailure: { picking = nil; errorMessage = $0.localizedDescription }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { preview != nil }, set: { if !$0 { preview = nil } }
        )) {
            if let preview {
                ReplicaPreviewView(payload: preview, onFinish: { dismiss() }, onReferenceChange: { photo in
                    selection.select(photo, for: .reference)
                    referenceThumbnail = replicaThumbnail(photo)
                })
            }
        }
        .alert(L10n.text("Unable to match colors"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.text("OK"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor
    private func generatePreview() async {
        guard selection.isComplete, !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            preview = try await selection.makePreview()
        } catch { errorMessage = error.localizedDescription }
    }
}

enum ReplicaPhotoSlot: String, Identifiable {
    case reference, target
    var id: String { rawValue }
}

/// Keep the picked image data together with readiness; a thumbnail alone cannot enable matching.
struct ReplicaPhotoSelection {
    private(set) var target: PickedPhoto?
    private(set) var reference: PickedPhoto?

    var isComplete: Bool { target != nil && reference != nil }
    var hintKey: String {
        if target == nil && reference == nil { return "Choose two photos to get started." }
        if target == nil { return "Add your photo to continue." }
        if reference == nil { return "Choose a reference photo to continue." }
        return "Ready to preview your new colors."
    }

    mutating func select(_ photo: PickedPhoto, for slot: ReplicaPhotoSlot) {
        switch slot {
        case .target: target = photo
        case .reference: reference = photo
        }
    }

    func makePreview() async throws -> ReplicaPreviewPayload {
        guard let target, let reference else { throw RecipeError.emptyImage }
        guard let original = ImageSourceFactory.decode(data: target.data, maximumDimension: 2048) else {
            throw ProjectRepositoryError.unreadableImage
        }
        let recipe = try await RecipeAnalyzer.analyze(data: reference.data, title: L10n.text("Reference Recipe"))
        return ReplicaPreviewPayload(target: target, reference: reference, original: original, recipe: recipe)
    }
}

struct ReplicaPreviewPayload: Identifiable {
    let id = UUID()
    let target: PickedPhoto
    let reference: PickedPhoto
    let original: OriginalImage
    let recipe: Recipe
}

private struct ReplicaPreviewView: View {
    let payload: ReplicaPreviewPayload
    let onFinish: () -> Void
    let onReferenceChange: (PickedPhoto) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: EditorSession
    @State private var referenceThumbnail: UIImage?
    @State private var recipe: Recipe
    @State private var strength = 70.0
    @State private var isComparing = false
    @State private var displayedImage: CGImage?
    @State private var presentsPicker = false
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedProject: PhotoProject?
    @State private var editorProject: PhotoProject?
    @State private var showsSaved = false
    private let repository = PhotoProjectRepository()

    init(payload: ReplicaPreviewPayload, onFinish: @escaping () -> Void,
         onReferenceChange: @escaping (PickedPhoto) -> Void) {
        self.payload = payload
        self.onFinish = onFinish
        self.onReferenceChange = onReferenceChange
        _session = StateObject(wrappedValue: EditorSession(original: payload.original))
        _referenceThumbnail = State(initialValue: replicaThumbnail(payload.reference))
        _recipe = State(initialValue: payload.recipe)
    }

    var body: some View {
        VStack(spacing: 0) {
            replicaHeader("Color Preview", back: { dismiss() })
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        previewImage
                            .frame(height: max(240, geometry.size.height - 190))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 16)
                        referenceCard(image: referenceThumbnail, selected: true, compact: true) { presentsPicker = true }
                            .padding(.horizontal, 20)
                        VStack(spacing: 8) {
                            HStack {
                                Text(L10n.text("Color Match Strength"))
                                Spacer()
                                Text("\(Int(strength))").monospacedDigit()
                            }
                            .font(FilmToneTheme.body)
                            Slider(value: $strength, in: 0...100, step: 1)
                                .tint(FilmToneTheme.accent)
                                .accessibilityLabel(L10n.text("Color Match Strength"))
                            HStack {
                                Text(L10n.text("Subtle"))
                                Spacer()
                                Text(L10n.text("Rich"))
                            }
                            .font(FilmToneTheme.caption).foregroundStyle(FilmToneTheme.secondaryText)
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(width: geometry.size.width)
                    .padding(.top, 8).padding(.bottom, 16)
                }
            }
            HStack(spacing: 12) {
                Button { Task { await save(continueEditing: true) } } label: {
                    Text(L10n.text("Continue Adjusting"))
                        .font(FilmToneTheme.button)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FilmToneTheme.divider))
                }
                Button { Task { await save(continueEditing: false) } } label: {
                    HStack {
                        if isSaving { ProgressView().tint(FilmToneTheme.primaryText) }
                        Text(L10n.text("Apply Colors"))
                    }
                }
                .buttonStyle(ReplicaPrimaryButtonStyle())
            }
            .padding(20)
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .toolbar(.hidden, for: .navigationBar)
        .buttonStyle(.plain)
        .disabled(isSaving || isAnalyzing)
        .task { session.previewRecipe(recipe, strength: strength / 100) }
        .onReceive(session.$preview) { state in
            if case .ready(let image) = state { displayedImage = image }
        }
        .onChange(of: strength) { value in session.previewRecipe(recipe, strength: value / 100) }
        .sheet(isPresented: $presentsPicker) {
            SystemPhotoPicker(
                selectionLimit: 1,
                onSelection: { photos in
                    presentsPicker = false
                    if let photo = photos.first { Task { await changeReference(photo) } }
                },
                onCancel: { presentsPicker = false },
                onFailure: { presentsPicker = false; errorMessage = $0.localizedDescription }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { editorProject != nil }, set: { if !$0 { editorProject = nil } }
        )) {
            if let editorProject {
                EditorView(original: payload.original, project: editorProject, repository: repository,
                           onRequestClose: onFinish, initialTool: .adjust, opensAdjustments: true)
            }
        }
        .alert(L10n.text("Unable to match colors"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.text("OK"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert(L10n.text("Colors Applied"), isPresented: $showsSaved) {
            Button(L10n.text("Done")) { onFinish() }
        } message: { Text(L10n.text("Saved to your projects. You can keep editing anytime.")) }
    }

    private var previewImage: some View {
        ImageCanvas(
            editedImage: currentPreviewImage,
            originalImage: session.originalPreview,
            isComparing: $isComparing,
            showsChrome: false
        )
        .overlay(alignment: .bottomTrailing) {
            Text(L10n.text(isComparing ? "Original" : "Hold to See Original"))
                .font(FilmToneTheme.caption)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(12)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in isComparing = true }
                    .onEnded { _ in isComparing = false })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isComparing.toggle() }
        }
        .overlay {
            if case .failed(let message) = session.preview {
                VStack(spacing: 12) {
                    Text(message).font(FilmToneTheme.caption)
                    Button(L10n.text("Retry")) { session.previewRecipe(recipe, strength: strength / 100) }
                }
                .padding()
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            } else if isAnalyzing {
                ProgressView(L10n.text("Analyzing reference…"))
            }
        }
    }

    private var currentPreviewImage: CGImage? {
        if case .ready(let image) = session.preview { return image }
        return displayedImage
    }

    @MainActor
    private func changeReference(_ photo: PickedPhoto) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let analyzed = try await RecipeAnalyzer.analyze(data: photo.data, title: L10n.text("Reference Recipe"))
            referenceThumbnail = replicaThumbnail(photo)
            recipe = analyzed
            onReferenceChange(photo)
            session.previewRecipe(analyzed, strength: strength / 100)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func save(continueEditing: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Import only on confirmation; browsing and replacing references creates no projects.
            if savedProject == nil {
                savedProject = try await repository.importPhoto(data: payload.target.data,
                    suggestedName: payload.target.suggestedName,
                    originalAssetIdentifier: payload.target.originalAssetIdentifier)
            }
            guard let project = savedProject else { return }
            let edits = session.editState
            let updated = try await repository.saveEditState(projectID: project.id, editState: edits,
                                                            commandSummary: L10n.text("Reference Color Match"))
            savedProject = updated
            let original = payload.original
            let thumbnail = try await Task.detached(priority: .utility) {
                try CoreImageRenderEngine().render(RenderRequest(original: original, edits: edits, maximumDimension: 512)).cgImage
            }.value
            try await repository.replaceThumbnail(thumbnail, for: updated)
            if continueEditing { editorProject = updated } else { showsSaved = true }
        } catch { errorMessage = error.localizedDescription }
    }
}

private func replicaThumbnail(_ photo: PickedPhoto) -> UIImage? {
    guard let source = ImageSourceFactory.decode(data: photo.data, maximumDimension: 1000),
          let image = try? CoreImageRenderEngine().render(RenderRequest(original: source, edits: .init(), maximumDimension: 1000)).cgImage
    else { return nil }
    return UIImage(cgImage: image)
}

private func replicaHeader(_ title: String, back: @escaping () -> Void) -> some View {
    Text(L10n.text(title))
        .font(FilmToneTheme.pageTitle)
        .frame(maxWidth: .infinity).frame(height: 52)
        .overlay(alignment: .leading) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.text("Back"))
        }
        .padding(.horizontal, 8)
}

private func referenceCard(image: UIImage?, selected: Bool, compact: Bool = false,
                           action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 14) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "plus").font(.system(size: 22, weight: .light)) }
            }
            .frame(width: compact ? 56 : 76, height: compact ? 56 : 76)
            .background(FilmToneTheme.chipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(selected ? "Reference Colors" : "Choose Reference Photo"))
                    .font(FilmToneTheme.body)
                if !compact {
                    Text(L10n.text("Use this photo's color mood."))
                        .font(FilmToneTheme.caption).foregroundStyle(FilmToneTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if compact { Text(L10n.text("Change")).font(FilmToneTheme.caption) }
            Image(systemName: "chevron.right").font(.system(size: 12))
        }
        .padding(12)
        .background(FilmToneTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
}

private struct ReplicaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(isEnabled ? Color(red: 0.10, green: 0.07, blue: 0.03) : Color(white: 0.85))
            .frame(maxWidth: .infinity).frame(minHeight: 54)
            .background(isEnabled ? FilmToneTheme.accent : Color(white: 0.22),
                        in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
