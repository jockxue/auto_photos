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
                            Text("AI Photo Studio").font(.largeTitle.bold())
                            Text("A non-destructive editing workspace built for fast, full-resolution renders.")
                                .foregroundStyle(.secondary)
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                AppIcon(systemName: "wand.and.stars")
                                Text("Start with the generated image").font(.title3.bold())
                                Text("No bundled asset is required. Explore every adjustment on a color-managed test image.")
                                    .foregroundStyle(.secondary)
                                NavigationLink {
                                    EditorView()
                                } label: {
                                    Label("Open Editor", systemImage: "arrow.right")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                            }
                        }

                        Button(action: openPicker) {
                            Label(isImporting ? "Importing…" : "Choose from Photos", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImporting)

                        if let statusMessage {
                            Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
                        }

                        if !projects.isEmpty {
                            Text("Projects").font(.title2.bold())
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
                                                Text("Created \(project.createdAt.formatted(date: .abbreviated, time: .omitted)) · Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
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
                                    Button("Versions") {
                                        versionProject = project
                                    }
                                    Button("Rename") {
                                        renameProject = project
                                        renameText = project.title
                                    }
                                    Button(project.isFavorite ? "Remove Favorite" : "Favorite") {
                                        Task { await toggleFavorite(project) }
                                    }
                                    Button("Delete", role: .destructive) {
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
                    onCancel: { statusMessage = "Photo selection was cancelled." },
                    onFailure: { statusMessage = "Photo read failed: \($0.localizedDescription)" }
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
            .alert("Rename Project", isPresented: Binding(
                get: { renameProject != nil },
                set: { if !$0 { renameProject = nil } }
            )) {
                TextField("Project name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
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
                        statusMessage = "Photo Library access is denied. The private system picker can still share selected photos."
                    }
                    presentsPicker = true
                }
            }
        } else {
            if status == .denied || status == .restricted {
                statusMessage = "Photo Library access is denied. The private system picker can still share selected photos."
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
            statusMessage = "Imported \(imported.count) photo\(imported.count == 1 ? "" : "s")."
            if let first = imported.first { await open(first) }
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func reloadProjects() async {
        do {
            projects = try await repository.allProjects()
        } catch {
            statusMessage = "Projects could not be loaded: \(error.localizedDescription)"
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
            statusMessage = "Project could not be opened: \(error.localizedDescription)"
        }
    }

    private func delete(_ project: PhotoProject) async {
        do {
            try await repository.delete(id: project.id)
            await reloadProjects()
        } catch {
            statusMessage = "Project could not be deleted: \(error.localizedDescription)"
        }
    }

    private func toggleFavorite(_ project: PhotoProject) async {
        do {
            var updated = project
            updated.isFavorite.toggle()
            _ = try await repository.update(updated)
            await reloadProjects()
        } catch {
            statusMessage = "Favorite could not be updated: \(error.localizedDescription)"
        }
    }

    private func rename(_ project: PhotoProject, to title: String) async {
        do {
            _ = try await repository.rename(id: project.id, title: title)
            renameProject = nil
            await reloadProjects()
        } catch {
            statusMessage = "Project could not be renamed: \(error.localizedDescription)"
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
                        Text("Version \(version.number)").font(.headline)
                        Text(version.commandSummary).foregroundStyle(.secondary)
                        Text(version.createdAt.formatted()).font(.caption)
                    }
                    Spacer()
                    if version.number == project.currentVersion {
                        Text("Current").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Restore") {
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
            .navigationTitle("Versions")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Restore Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
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
