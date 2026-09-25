import Photos
import SwiftUI

struct HomeView: View {
    private let repository = PhotoProjectRepository()

    @State private var projects: [PhotoProject] = []
    @State private var editorPayload: EditorPayload?
    @State private var presentsPicker = false
    @State private var isImporting = false
    @State private var statusMessage: String?

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
                                            VStack(alignment: .leading) {
                                                Text(project.title).font(.headline)
                                                Text("\(project.originalPixelWidth) × \(project.originalPixelHeight) · \(project.originalFormat.rawValue.uppercased())")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
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
                    suggestedName: photo.suggestedName
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
}

private struct EditorPayload: Identifiable {
    var id: UUID { project.id }
    let project: PhotoProject
    let original: OriginalImage
}
