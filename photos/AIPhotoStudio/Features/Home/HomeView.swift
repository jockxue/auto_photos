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
                FilmToneTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text("FilmTone"))
                                .font(FilmToneTheme.largeTitle)
                                .foregroundStyle(FilmToneTheme.primaryText)
                            Text(L10n.text("Give every photo its own color story."))
                                .font(FilmToneTheme.body)
                                .foregroundStyle(FilmToneTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("Start Creating")
                            HStack(alignment: .top, spacing: 10) {
                                NavigationLink {
                                    EditorView()
                                } label: {
                                    entryCard(
                                        systemImage: "wand.and.stars",
                                        title: "Open Editor",
                                        detail: "No bundled asset is required. Explore every adjustment on a color-managed test image."
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .top)

                                Button(action: openPicker) {
                                    entryCard(
                                        systemImage: isImporting ? "hourglass" : "photo.on.rectangle",
                                        title: isImporting ? "Importing…" : "Choose from Photos",
                                        detail: "Import a photo without changing the original."
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isImporting)
                                .frame(maxWidth: .infinity, alignment: .top)
                            }

                            NavigationLink {
                                PhotoManagementView()
                                    .onDisappear { Task { await reloadProjects() } }
                            } label: {
                                AppCard {
                                    HStack(spacing: 12) {
                                        AppIcon(systemName: "photo")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(L10n.text("Photo Library"))
                                                .font(FilmToneTheme.body.weight(.semibold))
                                                .foregroundStyle(FilmToneTheme.primaryText)
                                                .lineLimit(2)
                                            Text(L10n.text("Browse and edit photos from your library."))
                                                .font(FilmToneTheme.caption)
                                                .foregroundStyle(FilmToneTheme.secondaryText)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(FilmToneTheme.caption.weight(.semibold))
                                            .foregroundStyle(FilmToneTheme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(FilmToneTheme.caption)
                                .foregroundStyle(FilmToneTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("Recent Edits")
                            if projects.isEmpty {
                                AppCard {
                                    Text(L10n.text("No edited projects yet."))
                                        .font(FilmToneTheme.body)
                                        .foregroundStyle(FilmToneTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                                    spacing: 16
                                ) {
                                    ForEach(projects) { project in
                                        projectCell(project)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

    private func sectionTitle(_ key: String) -> some View {
        Text(L10n.text(key))
            .font(FilmToneTheme.sectionTitle)
            .foregroundStyle(FilmToneTheme.primaryText)
    }

    private func entryCard(systemImage: String, title: String, detail: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppIcon(systemName: systemImage)
                Text(L10n.text(title))
                    .font(FilmToneTheme.body.weight(.semibold))
                    .foregroundStyle(FilmToneTheme.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(L10n.text(detail))
                    .font(FilmToneTheme.caption)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func projectCell(_ project: PhotoProject) -> some View {
        Button {
            Task { await open(project) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ProjectThumbnail(project: project, repository: repository)
                    if project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(FilmToneTheme.accent)
                            .padding(6)
                    }
                }
                Text(project.title)
                    .font(FilmToneTheme.body.weight(.semibold))
                    .foregroundStyle(FilmToneTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FilmToneTheme.caption)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.format(
            "%@, %lld × %lld",
            project.title,
            Int64(project.originalPixelWidth),
            Int64(project.originalPixelHeight)
        )))
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
                    .foregroundStyle(FilmToneTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .background(FilmToneTheme.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: project.currentVersion) {
            guard
                let data = try? await repository.thumbnailData(for: project),
                let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return }
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}
