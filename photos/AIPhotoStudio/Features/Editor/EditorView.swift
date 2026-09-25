import SwiftUI

struct EditorView: View {
    enum Tool: String, CaseIterable, Hashable {
        case adjust = "Adjust"
        case filter = "Filter"
        case crop = "Crop"
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: EditorSession
    @State private var selectedAdjustment: AdjustmentKey = .exposure
    @State private var selectedTool: Tool = .adjust
    @State private var saveError: String?

    init(
        original: OriginalImage = ImageSourceFactory.makeTestImage(),
        project: PhotoProject? = nil,
        repository: PhotoProjectRepository? = nil
    ) {
        _session = StateObject(wrappedValue: EditorSession(
            original: original,
            project: project,
            repository: repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            ImageCanvas(editedImage: editedImage, originalImage: session.originalPreview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppToolbar {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Label(tool.rawValue, systemImage: tool.icon)
                    }
                    .tint(selectedTool == tool ? .indigo : .secondary)
                }
            }

            toolControls
        }
        .navigationBarBackButtonHidden()
        .alert("Unable to save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var editedImage: CGImage? {
        switch session.preview {
        case .ready(let image): image
        default: nil
        }
    }

    private var editorHeader: some View {
        HStack {
            Button(action: { dismiss() }) { Image(systemName: "chevron.left") }
                .accessibilityLabel("Back")
            Text(session.title).font(.headline).lineLimit(1)
            Spacer()
            Button(action: session.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!session.canUndo)
                .accessibilityLabel("Undo")
            Button(action: session.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!session.canRedo)
                .accessibilityLabel("Redo")
            Button("Done") {
                Task {
                    do {
                        try await session.complete()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var toolControls: some View {
        switch selectedTool {
        case .adjust:
            VStack {
                Menu {
                    ForEach(AdjustmentKey.allCases) { key in
                        Button(key.title) { selectedAdjustment = key }
                    }
                } label: {
                    Label(selectedAdjustment.title, systemImage: "slider.horizontal.3")
                }
                AppSlider(
                    title: selectedAdjustment.title,
                    value: Binding(
                        get: { session.value(for: selectedAdjustment) },
                        set: { session.setValue($0, for: selectedAdjustment) }
                    ),
                    range: selectedAdjustment.range
                )
            }
            .padding()
        case .filter:
            Text("Filter recipes plug into EditState without changing the original.")
                .font(.footnote).foregroundStyle(.secondary).padding()
        case .crop:
            Text("Crop and geometry are stored as normalized non-destructive edits.")
                .font(.footnote).foregroundStyle(.secondary).padding()
        }
    }
}

private extension EditorView.Tool {
    var icon: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .filter: "camera.filters"
        case .crop: "crop"
        }
    }
}
