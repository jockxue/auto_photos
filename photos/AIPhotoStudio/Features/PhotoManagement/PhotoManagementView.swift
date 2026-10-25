import Photos
import SwiftUI

struct PhotoManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PhotoLibraryViewModel()
    @State private var showsGrid = false
    @State private var editorPayload: ManagedEditorPayload?
    @State private var isOpeningEditor = false
    private let repository = PhotoProjectRepository()

    var body: some View {
        let page = ZStack {
            Color.black.ignoresSafeArea()
            if !showsGrid || model.needsPermissionPrompt || model.controller.isEmpty {
                content
            }
            VStack {
                topBar
                if model.authorization == .limited {
                    Text(L10n.text("Only the photos you selected are available."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 4)
                }
                if showsGrid && !model.needsPermissionPrompt && !model.controller.isEmpty {
                    photoGrid
                } else {
                    Spacer()
                    if model.controller.isDeleting {
                        ProgressView().tint(.white).padding(.bottom, 28)
                    }
                }
                if let error = model.controller.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(12)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sheet(item: $editorPayload) { payload in
            NavigationStack {
                EditorView(
                    original: payload.original,
                    project: payload.project,
                    repository: repository
                )
            }
        }

        if showsGrid {
            page
        } else {
            page.gesture(browseGesture)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsPermissionPrompt {
            permissionPrompt
        } else if model.controller.isEmpty && !model.isLoadingImage {
            emptyState
        } else {
            ZStack {
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if model.isLoadingImage && model.image == nil && !model.controller.isDeleting {
                    ProgressView().tint(.white)
                }
                if !model.controller.isEmpty && !model.controller.isDeleting {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .accessibilityLabel(L10n.text("Back"))
            Spacer()
            if let position = model.controller.positionText {
                Text(position)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
            if !model.needsPermissionPrompt && !model.controller.isEmpty {
                HStack(spacing: 4) {
                    Button {
                        showsGrid.toggle()
                    } label: {
                        Image(systemName: showsGrid ? "photo" : "square.grid.2x2")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .accessibilityLabel(L10n.text(showsGrid ? "Current Photo" : "All Photos"))
                    Button {
                        Task { await openInEditor() }
                    } label: {
                        Group {
                            if isOpeningEditor {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                    }
                    .accessibilityLabel(L10n.text("Edit"))
                    .disabled(model.controller.isDeleting || isOpeningEditor)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.25))
    }

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Text(permissionTitle).font(.title3.bold()).foregroundStyle(.white)
            Text(permissionDetail)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(model.authorization == .notDetermined ? L10n.text("Allow Photo Access") : L10n.text("Open Settings")) {
                if model.authorization == .notDetermined {
                    model.start()
                } else {
                    model.openSettings()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var emptyState: some View {
        Text(L10n.text("No photos in your library."))
            .foregroundStyle(.white.opacity(0.75))
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                spacing: 2
            ) {
                ForEach(model.assets, id: \.localIdentifier) { asset in
                    Button {
                        if let index = model.assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                            model.show(at: index)
                            showsGrid = false
                        }
                    } label: {
                        AssetThumbnail(asset: asset, load: model.thumbnail(for:))
                            .overlay {
                                if model.assets.indices.contains(model.controller.index),
                                   model.assets[model.controller.index].localIdentifier == asset.localIdentifier {
                                    Rectangle().strokeBorder(.white, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openInEditor() async {
        guard !isOpeningEditor else { return }
        isOpeningEditor = true
        defer { isOpeningEditor = false }
        do {
            guard let file = await model.currentPhotoFile() else {
                model.noteMessage(L10n.text("The photo could not be loaded."))
                return
            }
            let project = try repository.importPhoto(
                data: file.data,
                suggestedName: file.filename,
                originalAssetIdentifier: file.identifier
            )
            let stored = try repository.originalData(for: project)
            guard let original = ImageSourceFactory.decode(data: stored, maximumDimension: 2048) else {
                throw ProjectRepositoryError.unreadableImage
            }
            editorPayload = ManagedEditorPayload(project: project, original: original)
        } catch {
            model.noteMessage(L10n.format("Import failed: %@", error.localizedDescription))
        }
    }

    private var browseGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !model.controller.isDeleting else { return }
                let width = value.translation.width
                let height = value.translation.height
                if abs(width) > abs(height), abs(width) > 72 {
                    width < 0 ? model.showNext() : model.showPrevious()
                } else if height < -88, abs(height) > abs(width) {
                    model.deleteCurrent()
                }
            }
    }

    private var permissionTitle: String {
        switch model.authorization {
        case .denied, .restricted: L10n.text("Photo access is off")
        default: L10n.text("Photo access is needed")
        }
    }

    private var permissionDetail: String {
        switch model.authorization {
        case .denied, .restricted:
            L10n.text("Allow photo access in Settings to browse your library.")
        case .limited:
            L10n.text("Only the photos you selected are available.")
        default:
            L10n.text("This page reads photos from your library. It does not edit them.")
        }
    }
}

private struct ManagedEditorPayload: Identifiable {
    var id: UUID { project.id }
    let project: PhotoProject
    let original: OriginalImage
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    let load: (PHAsset) async -> UIImage?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: asset.localIdentifier) {
            image = await load(asset)
        }
    }
}
