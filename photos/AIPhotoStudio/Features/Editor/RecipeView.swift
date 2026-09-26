import SwiftUI

struct RecipeView: View {
    @ObservedObject var session: EditorSession
    @State private var recipes: [Recipe] = []
    @State private var draft: Recipe?
    @State private var strength = 100.0
    @State private var isAnalyzing = false
    @State private var presentsPicker = false
    @State private var statusMessage: String?
    @State private var saveTitle = ""
    @State private var presentsSave = false

    private let store = RecipeStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L10n.text("Choose Reference")) { presentsPicker = true }
                    .disabled(isAnalyzing)
                Button(L10n.text("Save Current as Recipe")) {
                    saveTitle = L10n.text("Untitled Recipe")
                    presentsSave = true
                }
            }
            .buttonStyle(.bordered)

            if isAnalyzing {
                ProgressView(L10n.text("Analyzing reference…"))
            }
            if let statusMessage {
                Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
            }
            if draft != nil {
                AppSlider(
                    title: L10n.text("Recipe Strength"),
                    value: Binding(
                        get: { strength },
                        set: { value in
                            strength = value
                            previewDraft()
                        }
                    ),
                    range: 0...100,
                    displayValue: { "\(Int($0.rounded()))%" },
                    onEditingChanged: { editing in
                        if editing {
                            session.beginRecipePreview()
                            previewDraft()
                        }
                    }
                )
                Button(L10n.text("Apply Recipe")) { applyDraft() }
                    .buttonStyle(.borderedProminent)
            }
            if !recipes.isEmpty {
                Text(L10n.text("Saved Recipes")).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recipes) { recipe in
                            Button(recipe.title) { select(recipe) }
                                .buttonStyle(.bordered)
                                .contextMenu {
                                    Button(L10n.text("Delete"), role: .destructive) {
                                        Task { await delete(recipe) }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding()
        .task { await reload() }
        .sheet(isPresented: $presentsPicker) {
            SystemPhotoPicker(
                maximumPixelSize: 512,
                onSelection: { photos in Task { await analyze(photos) } },
                onCancel: {},
                onFailure: { statusMessage = $0.localizedDescription }
            )
        }
        .alert(L10n.text("Save Recipe"), isPresented: $presentsSave) {
            TextField(L10n.text("Recipe name"), text: $saveTitle)
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Save")) {
                Task { await saveCurrent() }
            }
        }
    }

    private func previewDraft() {
        guard let draft else { return }
        session.previewRecipe(draft, strength: strength / 100)
    }

    private func applyDraft() {
        guard let draft else { return }
        session.commitRecipe(draft, strength: strength / 100)
        statusMessage = L10n.format("Applied %@", draft.title)
    }

    private func select(_ recipe: Recipe) {
        session.cancelRecipePreview()
        draft = recipe
        strength = 100
        session.commitRecipe(recipe, strength: 1)
        statusMessage = L10n.format("Applied %@", recipe.title)
    }

    private func analyze(_ photos: [PickedPhoto]) async {
        presentsPicker = false
        isAnalyzing = true
        statusMessage = nil
        defer { isAnalyzing = false }
        do {
            guard let photo = photos.first else { throw RecipeError.emptyImage }
            let recipe = try await RecipeAnalyzer.analyze(
                data: photo.data,
                title: photo.suggestedName ?? L10n.text("Reference Recipe")
            )
            session.cancelRecipePreview()
            draft = recipe
            strength = 100
            session.commitRecipe(recipe, strength: 1)
            statusMessage = L10n.text("Reference recipe is ready.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveCurrent() async {
        do {
            let recipe = try session.makeRecipe(title: saveTitle)
            try await store.save(recipe)
            await reload()
            statusMessage = L10n.format("Saved %@", recipe.title)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func delete(_ recipe: Recipe) async {
        do {
            try await store.delete(id: recipe.id)
            if draft?.id == recipe.id { draft = nil }
            await reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            recipes = try await store.fetchAll()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
