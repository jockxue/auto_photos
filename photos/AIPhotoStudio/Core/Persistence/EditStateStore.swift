import Foundation

protocol EditStateStore {
    func load(documentID: UUID) async throws -> EditState?
    func save(_ state: EditState, documentID: UUID) async throws
}

/// iOS 16-compatible persistence path. The app can migrate these Codable recipes
/// into SwiftData records when running on iOS 17 or later.
actor JSONEditStateStore: EditStateStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("EditStates", isDirectory: true)
    }

    func load(documentID: UUID) async throws -> EditState? {
        let url = fileURL(documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(EditState.self, from: Data(contentsOf: url))
    }

    func save(_ state: EditState, documentID: UUID) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: fileURL(documentID), options: .atomic)
    }

    private func fileURL(_ documentID: UUID) -> URL {
        directory.appendingPathComponent(documentID.uuidString).appendingPathExtension("json")
    }
}
