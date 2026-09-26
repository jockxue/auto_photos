import Photos
import ImageIO
import SwiftUI

struct HomeView: View {
    private let repository = PhotoProjectRepository()

    @State private var projects: [PhotoProject] = []
    @State private var editorPayload: EditorPayload?
    @State private var presentsPicker = false
    @State private var isImporting = false
    @State private var statusMessage: String?
    @State private var renameProject: PhotoProject?
    @State private var renameText = ""
    @State private var versionProject: PhotoProject?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.2), .purple.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("AI Photo Studio")).font(.largeTitle.bold())
                            Text(L10n.text("A non-destructive editing workspace built for fast, full-resolution renders."))
                                .foregroundStyle(.secondary)
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                AppIcon(systemName: "wand.and.stars")
                                Text(L10n.text("Start with the generated image")).font(.title3.bold())
                                Text(L10n.text("No bundled asset is required. Explore every adjustment on a color-managed test image."))
                                    .foregroundStyle(.secondary)
                                NavigationLink {
                                    EditorView()
                                } label: {
                                    Label(L10n.text("Open Editor"), systemImage: "arrow.right")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                            }
                        }

                        Button(action: openPicker) {
                            Label(L10n.text(isImporting ? "Importing…" : "Choose from Photos"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImporting)

                        if let statusMessage {
                            Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
                        }

                        if !projects.isEmpty {
                            Text(L10n.text("Projects")).font(.title2.bold())
                            ForEach(projects) { project in
                                Button {
                                    Task { await open(project) }
                                } label: {
                                    AppCard {
                                        HStack {
                                            ProjectThumbnail(project: project, repository: repository)
                                            VStack(alignment: .leading) {
                                                Text(project.title).font(.headline)
                                                Text("\(project.originalPixelWidth) × \(project.originalPixelHeight) · \(project.originalFormat.rawValue.uppercased()) · v\(project.currentVersion)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                Text(L10n.format(
                                                    "Created %@ · Updated %@",
                                                    project.createdAt.formatted(date: .abbreviated, time: .omitted),
                                                    project.updatedAt.formatted(date: .abbreviated, time: .shortened)
                                                ))
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if project.isFavorite {
                                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                            }
                                            Image(systemName: "chevron.right")
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(L10n.text("Versions")) {
                                        versionProject = project
                                    }
                                    Button(L10n.text("Rename")) {
                                        renameProject = project
                                        renameText = project.title
                                    }
                                    Button(L10n.text(project.isFavorite ? "Remove Favorite" : "Favorite")) {
                                        Task { await toggleFavorite(project) }
                                    }
                                    Button(L10n.text("Delete"), role: .destructive) {
                                        Task { await delete(project) }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .task { await reloadProjects() }
            .sheet(isPresented: $presentsPicker) {
                SystemPhotoPicker(
                    onSelection: { photos in Task { await importPhotos(photos) } },
                    onCancel: { statusMessage = L10n.text("Photo selection was cancelled.") },
                    onFailure: { statusMessage = L10n.format("Photo read failed: %@", $0.localizedDescription) }
                )
            }
            .sheet(item: $editorPayload, onDismiss: {
                Task { await reloadProjects() }
            }) { payload in
                NavigationStack {
                    EditorView(
                        original: payload.original,
                        project: payload.project,
                        repository: repository
                    )
                }
            }
            .sheet(item: $versionProject, onDismiss: {
                Task { await reloadProjects() }
            }) { project in
                VersionHistoryView(project: project, repository: repository)
            }
            .alert(L10n.text("Rename Project"), isPresented: Binding(
                get: { renameProject != nil },
                set: { if !$0 { renameProject = nil } }
            )) {
                TextField(L10n.text("Project name"), text: $renameText)
                Button(L10n.text("Cancel"), role: .cancel) {}
                Button(L10n.text("Save")) {
                    guard let project = renameProject else { return }
                    Task { await rename(project, to: renameText) }
                }
            }
        }
    }

    private func openPicker() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    if newStatus == .denied || newStatus == .restricted {
                        statusMessage = L10n.text("Photo Library access is denied. The private system picker can still share selected photos.")
                    }
                    presentsPicker = true
                }
            }
        } else {
            if status == .denied || status == .restricted {
                statusMessage = L10n.text("Photo Library access is denied. The private system picker can still share selected photos.")
            }
            presentsPicker = true
        }
    }

    private func importPhotos(_ photos: [PickedPhoto]) async {
        presentsPicker = false
        isImporting = true
        statusMessage = nil
        defer { isImporting = false }

        do {
            var imported: [PhotoProject] = []
            for photo in photos {
                imported.append(try await repository.importPhoto(
                    data: photo.data,
                    suggestedName: photo.suggestedName,
                    originalAssetIdentifier: photo.originalAssetIdentifier
                ))
            }
            await reloadProjects()
            statusMessage = L10n.format("Imported %lld photos.", imported.count)
            if let first = imported.first { await open(first) }
        } catch {
            statusMessage = L10n.format("Import failed: %@", error.localizedDescription)
        }
    }

    private func reloadProjects() async {
        do {
            projects = try await repository.allProjects()
        } catch {
            statusMessage = L10n.format("Projects could not be loaded: %@", error.localizedDescription)
        }
    }

    private func open(_ project: PhotoProject) async {
        do {
            let data = try await repository.originalData(for: project)
            guard let original = ImageSourceFactory.decode(data: data, maximumDimension: 2048) else {
                throw ProjectRepositoryError.unreadableImage
            }
            editorPayload = EditorPayload(project: project, original: original)
        } catch {
            statusMessage = L10n.format("Project could not be opened: %@", error.localizedDescription)
        }
    }

    private func delete(_ project: PhotoProject) async {
        do {
            try await repository.delete(id: project.id)
            await reloadProjects()
        } catch {
            statusMessage = L10n.format("Project could not be deleted: %@", error.localizedDescription)
        }
    }

    private func toggleFavorite(_ project: PhotoProject) async {
        do {
            var updated = project
            updated.isFavorite.toggle()
            _ = try await repository.update(updated)
            await reloadProjects()
        } catch {
            statusMessage = L10n.format("Favorite could not be updated: %@", error.localizedDescription)
        }
    }

    private func rename(_ project: PhotoProject, to title: String) async {
        do {
            _ = try await repository.rename(id: project.id, title: title)
            renameProject = nil
            await reloadProjects()
        } catch {
            statusMessage = L10n.format("Project could not be renamed: %@", error.localizedDescription)
        }
    }
}

private struct VersionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let project: PhotoProject
    let repository: PhotoProjectRepository
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(project.versions.sorted { $0.number > $1.number }) { version in
                HStack {
                    VStack(alignment: .leading) {
                        Text(L10n.format("Version %lld", version.number)).font(.headline)
                        Text(L10n.text(version.commandSummary)).foregroundStyle(.secondary)
                        Text(version.createdAt.formatted()).font(.caption)
                    }
                    Spacer()
                    if version.number == project.currentVersion {
                        Text(L10n.text("Current")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(L10n.text("Restore")) {
                            Task {
                                do {
                                    let restored = try await repository.restore(
                                        projectID: project.id,
                                        version: version.number
                                    )
                                    let data = try await repository.originalData(for: restored)
                                    guard let original = ImageSourceFactory.decode(
                                        data: data,
                                        maximumDimension: 512
                                    ) else {
                                        throw ProjectRepositoryError.unreadableImage
                                    }
                                    let thumbnail = try CoreImageRenderEngine().render(RenderRequest(
                                        original: original,
                                        edits: restored.editState,
                                        maximumDimension: 512
                                    )).cgImage
                                    try await repository.replaceThumbnail(thumbnail, for: restored)
                                    dismiss()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("Versions"))
            .toolbar { Button(L10n.text("Done")) { dismiss() } }
            .alert(L10n.text("Restore Failed"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.text("OK"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct EditorPayload: Identifiable {
    var id: UUID { project.id }
    let project: PhotoProject
    let original: OriginalImage
}

private struct ProjectThumbnail: View {
    let project: PhotoProject
    let repository: PhotoProjectRepository
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: project.currentVersion) {
            guard
                let data = try? await repository.thumbnailData(for: project),
                let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return }
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}
