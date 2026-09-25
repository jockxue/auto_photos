import CoreGraphics
import CoreImage
import Foundation
import ImageIO

struct ImageMetadata: Equatable, @unchecked Sendable {
    let pixelSize: CGSize
    let orientation: CGImagePropertyOrientation
    let scale: CGFloat
    let hasAlpha: Bool
    let colorSpace: CGColorSpace?

    static func == (lhs: ImageMetadata, rhs: ImageMetadata) -> Bool {
        let lhsColorSpaceName = lhs.colorSpace?.name.map { $0 as String }
        let rhsColorSpaceName = rhs.colorSpace?.name.map { $0 as String }
        return lhs.pixelSize == rhs.pixelSize
            && lhs.orientation == rhs.orientation
            && lhs.scale == rhs.scale
            && lhs.hasAlpha == rhs.hasAlpha
            && lhsColorSpaceName == rhsColorSpaceName
    }
}

/// Immutable source pixels plus the metadata needed for faithful export.
struct OriginalImage: @unchecked Sendable {
    let image: CIImage
    let metadata: ImageMetadata

    init(image: CIImage, metadata: ImageMetadata) {
        self.image = image
        self.metadata = metadata
    }
}

struct PhotoDocument: Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let original: OriginalImage
    var editState: EditState

    init(id: UUID = UUID(), createdAt: Date = .now, original: OriginalImage, editState: EditState = .init()) {
        self.id = id
        self.createdAt = createdAt
        self.original = original
        self.editState = editState
    }
}
