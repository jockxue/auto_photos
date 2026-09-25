import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class StoredEditState {
    @Attribute(.unique) var documentID: UUID
    var payload: Data
    var modifiedAt: Date

    init(documentID: UUID, payload: Data, modifiedAt: Date = .now) {
        self.documentID = documentID
        self.payload = payload
        self.modifiedAt = modifiedAt
    }
}

/// Optional iOS 17+ backend. All use sites must be availability-gated; the
/// JSON store remains the valid implementation for the iOS 16 deployment target.
@available(iOS 17.0, *)
@MainActor
final class SwiftDataEditStateStore: EditStateStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func load(documentID: UUID) async throws -> EditState? {
        let id = documentID
        var descriptor = FetchDescriptor<StoredEditState>(
            predicate: #Predicate { $0.documentID == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        return try JSONDecoder().decode(EditState.self, from: record.payload)
    }

    func save(_ state: EditState, documentID: UUID) async throws {
        let payload = try JSONEncoder().encode(state)
        let id = documentID
        var descriptor = FetchDescriptor<StoredEditState>(
            predicate: #Predicate { $0.documentID == id }
        )
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.payload = payload
            record.modifiedAt = .now
        } else {
            context.insert(StoredEditState(documentID: id, payload: payload))
        }
        try context.save()
    }
}
