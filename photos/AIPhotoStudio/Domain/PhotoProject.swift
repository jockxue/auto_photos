import CoreGraphics
import Foundation

enum PhotoFormat: String, Codable, Sendable {
    case jpeg, heic, png
}

/// Persisted project metadata. The original file is immutable and referenced by
/// relative path; completing an edit only updates this recipe and metadata.
struct PhotoProject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let originalFilename: String
    let originalFormat: PhotoFormat
    let originalPixelWidth: Int
    let originalPixelHeight: Int
    let createdAt: Date
    var updatedAt: Date
    var editState: EditState

    init(
        id: UUID = UUID(),
        title: String,
        originalFilename: String,
        originalFormat: PhotoFormat,
        originalPixelWidth: Int,
        originalPixelHeight: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        editState: EditState = .init()
    ) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.originalFormat = originalFormat
        self.originalPixelWidth = originalPixelWidth
        self.originalPixelHeight = originalPixelHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.editState = editState
    }
}
