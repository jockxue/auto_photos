import Foundation

actor RecipeStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("AIPhotoStudio", isDirectory: true)
        fileURL = directory.appendingPathComponent("recipes.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ recipe: Recipe) throws {
        var recipes = try load()
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        try write(recipes)
    }

    func fetchAll() throws -> [Recipe] {
        try load().sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: UUID) throws {
        var recipes = try load()
        guard recipes.contains(where: { $0.id == id }) else { throw RecipeError.recipeNotFound }
        recipes.removeAll { $0.id == id }
        try write(recipes)
    }

    func get(id: UUID) throws -> Recipe {
        guard let recipe = try load().first(where: { $0.id == id }) else {
            throw RecipeError.recipeNotFound
        }
        return recipe
    }

    private func load() throws -> [Recipe] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try decoder.decode([Recipe].self, from: Data(contentsOf: fileURL))
        } catch {
            throw RecipeError.readFailed
        }
    }

    private func write(_ recipes: [Recipe]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(recipes).write(to: fileURL, options: .atomic)
        } catch {
            throw RecipeError.saveFailed
        }
    }
}
