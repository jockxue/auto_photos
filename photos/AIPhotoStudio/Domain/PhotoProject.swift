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
    /// PHPicker only supplies this for Photos-library-backed results when the
    /// system permits identification. Privacy-preserving/file-provider results
    /// legitimately have no identifier.
    let originalAssetIdentifier: String?
    /// Repository-root-relative paths; absolute/user-provided paths are rejected.
    let originalImagePath: String
    let thumbnailPath: String
    let originalFormat: PhotoFormat
    let originalPixelWidth: Int
    let originalPixelHeight: Int
    let createdAt: Date
    private(set) var updatedAt: Date
    /// Starts at 1 and advances once for each successful repository update.
    private(set) var currentVersion: Int
    var isFavorite: Bool
    var editState: EditState

    init(
        id: UUID = UUID(),
        title: String,
        originalAssetIdentifier: String?,
        originalImagePath: String,
        thumbnailPath: String,
        originalFormat: PhotoFormat,
        originalPixelWidth: Int,
        originalPixelHeight: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        currentVersion: Int = 1,
        isFavorite: Bool = false,
        editState: EditState = .init()
    ) {
        self.id = id
        self.title = title
        self.originalAssetIdentifier = originalAssetIdentifier
        self.originalImagePath = originalImagePath
        self.thumbnailPath = thumbnailPath
        self.originalFormat = originalFormat
        self.originalPixelWidth = originalPixelWidth
        self.originalPixelHeight = originalPixelHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentVersion = currentVersion
        self.isFavorite = isFavorite
        self.editState = editState
    }

    mutating func markUpdated(version: Int, at date: Date = .now) {
        precondition(version > currentVersion)
        currentVersion = version
        updatedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, originalAssetIdentifier, originalImagePath, thumbnailPath
        case originalFilename // Legacy first-phase key.
        case originalFormat, originalPixelWidth, originalPixelHeight
        case createdAt, updatedAt, currentVersion, isFavorite, editState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        originalAssetIdentifier = try values.decodeIfPresent(String.self, forKey: .originalAssetIdentifier)
        if let path = try values.decodeIfPresent(String.self, forKey: .originalImagePath) {
            originalImagePath = path
        } else {
            let filename = try values.decode(String.self, forKey: .originalFilename)
            originalImagePath = "Originals/\(filename)"
        }
        thumbnailPath = try values.decodeIfPresent(String.self, forKey: .thumbnailPath)
            ?? "Thumbnails/\(id.uuidString).jpg"
        originalFormat = try values.decode(PhotoFormat.self, forKey: .originalFormat)
        originalPixelWidth = try values.decode(Int.self, forKey: .originalPixelWidth)
        originalPixelHeight = try values.decode(Int.self, forKey: .originalPixelHeight)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        currentVersion = try values.decodeIfPresent(Int.self, forKey: .currentVersion) ?? 1
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        editState = try values.decode(EditState.self, forKey: .editState)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(originalAssetIdentifier, forKey: .originalAssetIdentifier)
        try values.encode(originalImagePath, forKey: .originalImagePath)
        try values.encode(thumbnailPath, forKey: .thumbnailPath)
        try values.encode(originalFormat, forKey: .originalFormat)
        try values.encode(originalPixelWidth, forKey: .originalPixelWidth)
        try values.encode(originalPixelHeight, forKey: .originalPixelHeight)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(currentVersion, forKey: .currentVersion)
        try values.encode(isFavorite, forKey: .isFavorite)
        try values.encode(editState, forKey: .editState)
    }
}
