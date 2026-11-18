import ImageIO
import SwiftUI
import UIKit

struct HomeView: View {
    private let repository = PhotoProjectRepository()

    @State private var projects: [PhotoProject] = []
    @State private var path: [HomeRoute] = []
    @State private var statusMessage: String?
    @State private var renameProject: PhotoProject?
    @State private var renameText = ""
    @State private var versionProject: PhotoProject?
    @State private var section: HomeSection = .home

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FilmToneTheme.background.ignoresSafeArea()

                Group {
                    if section == .home {
                        homeContent
                    } else {
                        ProfileView(projects: projects)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HomeTabBar(selection: $section)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self, destination: destination)
            .task { await reloadProjects() }
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
        .onChange(of: path) { path in
            if path.isEmpty { Task { await reloadProjects() } }
        }
    }

    @ViewBuilder
    private func destination(_ route: HomeRoute) -> some View {
        switch route {
        case .pickPhoto:
            PhotoSelectionView { photo in
                try await openEditor(importing: photo, tool: .filter)
            }
        case .replica:
            ColorReplicaView { project, original in
                showEditor(project: project, original: original, tool: .filter)
            }
        case .editor(let editor):
            EditorView(
                original: editor.original,
                project: editor.project,
                repository: repository,
                onRequestClose: { path.removeAll() },
                initialTool: editor.tool
            )
        }
    }

    private var homeContent: some View {
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
                                NavigationLink(value: HomeRoute.pickPhoto) {
                                    featureCard(
                                        title: "Apply a Preset",
                                        detail: "Explore film styles",
                                        imageName: "HomeApplyPreset"
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .top)

                                NavigationLink(value: HomeRoute.replica) {
                                    featureCard(
                                        title: "Match Colors",
                                        detail: "Copy a reference photo's color",
                                        imageName: "HomeMatchColors"
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(FilmToneTheme.caption)
                                .foregroundStyle(FilmToneTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("My Projects")
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
                    .padding(.bottom, 16)
                }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(L10n.text(key))
            .font(FilmToneTheme.sectionTitle)
            .foregroundStyle(FilmToneTheme.primaryText)
    }

    private func featureCard(title: String, detail: String, imageName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: bundledImage(imageName))
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipped()
                .padding(.top, 1)
                .padding(.horizontal, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FilmToneTheme.primaryText)
                    .lineLimit(1)
                Text(L10n.text(detail))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(FilmToneTheme.featureCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bundledImage(_ name: String) -> UIImage {
        if let image = UIImage(named: name) {
            return image
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return UIImage()
        }
        return image
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

    private func openEditor(importing photo: PickedPhoto, tool: EditorView.Tool) async throws {
        let project = try await repository.project(for: photo)
        let original = try await decodedOriginal(for: project)
        showEditor(project: project, original: original, tool: tool)
    }

    private func showEditor(project: PhotoProject, original: OriginalImage, tool: EditorView.Tool) {
        path = [.editor(EditorRoute(project: project, original: original, tool: tool))]
    }

    private func decodedOriginal(for project: PhotoProject) async throws -> OriginalImage {
        let data = try await repository.originalData(for: project)
        guard let original = ImageSourceFactory.decode(data: data, maximumDimension: 2048) else {
            throw ProjectRepositoryError.unreadableImage
        }
        return original
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
            let original = try await decodedOriginal(for: project)
            showEditor(project: project, original: original, tool: .filter)
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

private enum HomeRoute: Hashable {
    case pickPhoto
    case replica
    case editor(EditorRoute)
}

/// `OriginalImage` is not hashable, so each push is identified by its own id.
private struct EditorRoute: Hashable {
    let id = UUID()
    let project: PhotoProject
    let original: OriginalImage
    let tool: EditorView.Tool

    static func == (lhs: EditorRoute, rhs: EditorRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PhotoProjectRepository {
    /// Reopens the existing project for a library photo instead of importing a duplicate.
    func project(for photo: PickedPhoto) throws -> PhotoProject {
        if let identifier = photo.originalAssetIdentifier,
           let existing = try allProjects().first(where: { $0.originalAssetIdentifier == identifier }) {
            return existing
        }
        return try importPhoto(
            data: photo.data,
            suggestedName: photo.suggestedName,
            originalAssetIdentifier: photo.originalAssetIdentifier
        )
    }
}

private struct ProjectThumbnail: View {
    let project: PhotoProject
    let repository: PhotoProjectRepository
    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
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
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(FilmToneTheme.chipBackground)
                    .clipped()
                }
            }
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

private enum HomeSection: Hashable {
    case home
    case profile
}

private struct HomeTabBar: View {
    @Binding var selection: HomeSection

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FilmToneTheme.divider)
                .frame(height: 1)
            HStack(spacing: 0) {
                tab(.home, symbol: "house", title: "Home")
                tab(.profile, symbol: "person", title: "Profile")
            }
            .padding(.horizontal, 46)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(FilmToneTheme.tabBar.ignoresSafeArea(edges: .bottom))
    }

    private func tab(_ section: HomeSection, symbol: String, title: String) -> some View {
        let selected = selection == section
        let color = selected ? FilmToneTheme.accent : FilmToneTheme.tabInactive
        return Button {
            selection = section
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 23, height: 23)
                Text(L10n.text(title))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
